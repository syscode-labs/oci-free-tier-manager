"""
OCI Free Tier Infrastructure Pipeline

Handles:
- Building Packer images (base + Proxmox)
- Uploading to OCI Object Storage
- Creating OCI custom images
- Validation
"""

import dagger
from dagger import dag, function, object_type
from typing import Annotated
import os


@object_type
class Main:
    """Main pipeline for OCI Free Tier infrastructure"""
    
    @function
    async def build_base_image(
        self,
        source: Annotated[
            dagger.Directory,
            dagger.Doc("Source directory with Packer configs")
        ]
    ) -> dagger.Directory:
        """
        Build base hardened image with Packer
        
        Returns directory with base-hardened.qcow2
        """
        return await (
            dag.container()
            .from_("hashicorp/packer:latest")
            
            # Install dependencies for QEMU
            .with_exec(["apk", "add", "--no-cache", "qemu-img", "qemu-system-x86_64"])
            
            # Copy Packer configs
            .with_directory("/work", source.directory("packer"))
            .with_workdir("/work")
            
            # Initialize Packer
            .with_exec(["packer", "init", "."])
            
            # Build base image
            .with_exec([
                "packer", "build",
                "-force",
                "-var", "headless=true",
                "base-hardened.pkr.hcl"
            ])
            
            # Return output directory
            .directory("/work/output-qemu")
        )
    
    @function
    async def build_proxmox_image(
        self,
        source: Annotated[dagger.Directory, dagger.Doc("Source directory")],
        base_image: Annotated[dagger.Directory, dagger.Doc("Base image directory")]
    ) -> dagger.Directory:
        """
        Build Proxmox image from base
        
        Returns directory with proxmox-ampere.qcow2
        """
        return await (
            dag.container()
            .from_("hashicorp/packer:latest")
            
            # Install dependencies
            .with_exec(["apk", "add", "--no-cache", "qemu-img", "qemu-system-x86_64"])
            
            # Copy Packer configs
            .with_directory("/work", source.directory("packer"))
            
            # Copy base image
            .with_directory("/work/base", base_image)
            
            .with_workdir("/work")
            
            # Initialize Packer
            .with_exec(["packer", "init", "."])
            
            # Build Proxmox image
            .with_exec([
                "packer", "build",
                "-force",
                "-var", "headless=true",
                "-var", "source_image=/work/base/base-hardened.qcow2",
                "proxmox-ampere.pkr.hcl"
            ])
            
            # Return output directory
            .directory("/work/output-qemu")
        )
    
    @function
    async def build_all_images(
        self,
        source: Annotated[
            dagger.Directory,
            dagger.Doc("Source directory with Packer configs")
        ] = None
    ) -> str:
        """
        Build both images sequentially and export to host
        
        Returns success message with artifact locations
        """
        # Use current directory if not provided
        if source is None:
            source = dag.host().directory(".")
        
        print("Building base image...")
        base = await self.build_base_image(source)
        
        print("Building Proxmox image...")
        proxmox = await self.build_proxmox_image(source, base)
        
        # Export to host
        print("Exporting images to ./artifacts/...")
        await base.export("./artifacts/base-hardened")
        await proxmox.export("./artifacts/proxmox-ampere")
        
        # Get image sizes
        base_files = await base.entries()
        proxmox_files = await proxmox.entries()
        
        return f"""
✓ Images built successfully!

Artifacts:
  - Base image: ./artifacts/base-hardened/{base_files[0] if base_files else 'base-hardened.qcow2'}
  - Proxmox image: ./artifacts/proxmox-ampere/{proxmox_files[0] if proxmox_files else 'proxmox-ampere.qcow2'}

Next steps:
  1. Validate: task build:validate
  2. Upload to OCI: task build:upload
  3. Deploy infrastructure: task deploy:oci
"""
    
    @function
    async def upload_to_oci(
        self,
        bucket: Annotated[str, dagger.Doc("OCI Object Storage bucket name")],
        compartment_id: Annotated[str, dagger.Doc("OCI compartment OCID")],
        region: Annotated[str, dagger.Doc("OCI region")] = "uk-london-1"
    ) -> str:
        """
        Upload images to OCI Object Storage and create custom images
        
        Requires OCI CLI authentication via ~/.oci/config
        """
        # Read artifacts from host
        artifacts = dag.host().directory("./artifacts")
        
        # Read OCI config from host
        oci_config_dir = dag.host().directory(f"{os.environ.get('HOME')}/.oci")
        
        # Upload base image
        result = await (
            dag.container()
            .from_("ghcr.io/oracle/oci-cli:latest")
            .with_directory("/artifacts", artifacts)
            .with_directory("/root/.oci", oci_config_dir)
            
            # Upload base image
            .with_exec([
                "oci", "os", "object", "put",
                "--bucket-name", bucket,
                "--file", "/artifacts/base-hardened/base-hardened.qcow2",
                "--name", "base-hardened.qcow2",
                "--force"
            ])
            
            # Upload Proxmox image
            .with_exec([
                "oci", "os", "object", "put",
                "--bucket-name", bucket,
                "--file", "/artifacts/proxmox-ampere/proxmox-ampere.qcow2",
                "--name", "proxmox-ampere.qcow2",
                "--force"
            ])
            
            # Verify total size < 20GB
            .with_exec([
                "sh", "-c",
                f"oci os object list --bucket-name {bucket} "
                "--query 'data[].\"size\"' | "
                "jq 'add' | "
                "awk '{if ($1 > 21474836480) exit 1}' || "
                "(echo 'ERROR: Total size exceeds 20GB!' && exit 1)"
            ])
            
            # Create custom images
            .with_exec([
                "oci", "compute", "image", "create",
                "--compartment-id", compartment_id,
                "--display-name", "base-hardened",
                "--bucket-name", bucket,
                "--object-name", "base-hardened.qcow2",
                "--region", region
            ])
            
            .with_exec([
                "oci", "compute", "image", "create",
                "--compartment-id", compartment_id,
                "--display-name", "proxmox-ampere",
                "--bucket-name", bucket,
                "--object-name", "proxmox-ampere.qcow2",
                "--region", region
            ])
            
            .stdout()
        )
        
        return f"✓ Images uploaded to OCI Object Storage and custom images created\n{result}"
    
    @function
    async def validate_images(
        self,
        max_size_gb: Annotated[int, dagger.Doc("Max size per image in GB")] = 10
    ) -> str:
        """
        Validate that built images meet size requirements
        
        Returns validation report
        """
        artifacts = dag.host().directory("./artifacts")
        
        result = await (
            dag.container()
            .from_("alpine:latest")
            .with_exec(["apk", "add", "--no-cache", "qemu-img", "jq"])
            .with_directory("/artifacts", artifacts)
            .with_exec([
                "sh", "-c",
                """
                set -e
                echo "Validating image sizes..."
                
                BASE_SIZE=$(qemu-img info --output=json /artifacts/base-hardened/*.qcow2 | jq '.["virtual-size"]')
                PROXMOX_SIZE=$(qemu-img info --output=json /artifacts/proxmox-ampere/*.qcow2 | jq '.["virtual-size"]')
                TOTAL_SIZE=$((BASE_SIZE + PROXMOX_SIZE))
                MAX_SIZE=$((21474836480))  # 20GB in bytes
                
                echo "Base image: $(($BASE_SIZE / 1024 / 1024 / 1024))GB"
                echo "Proxmox image: $(($PROXMOX_SIZE / 1024 / 1024 / 1024))GB"
                echo "Total: $(($TOTAL_SIZE / 1024 / 1024 / 1024))GB / 20GB"
                
                if [ $TOTAL_SIZE -gt $MAX_SIZE ]; then
                    echo "ERROR: Total size exceeds 20GB OCI free tier limit!"
                    exit 1
                fi
                
                echo "✓ Images within size limits"
                """
            ])
            .stdout()
        )
        
        return result
