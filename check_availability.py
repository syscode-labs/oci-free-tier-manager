#!/usr/bin/env python3
"""
OCI Free Tier Availability Checker

This script checks the availability of OCI Always Free compute instances
by attempting to query the OCI API. It can be run periodically (e.g., via cron)
to monitor when free tier capacity becomes available.

Required: OCI CLI installed and configured with valid credentials
Install: pip install oci-cli
Configure: oci setup config
"""

import sys
import json
import subprocess
from datetime import datetime
from typing import Dict, List, Any


def log(message: str) -> None:
    """Log message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}")


def run_oci_command(command: List[str]) -> Dict[str, Any]:
    """Execute OCI CLI command and return JSON result"""
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=True
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        log(f"Error executing command: {e}")
        log(f"stderr: {e.stderr}")
        return {}
    except json.JSONDecodeError as e:
        log(f"Error parsing JSON response: {e}")
        return {}


def check_ampere_availability(compartment_id: str, availability_domain: str) -> bool:
    """
    Check if Ampere A1 instances can be launched
    
    Returns True if capacity is available, False otherwise
    """
    log(f"Checking Ampere A1 availability in {availability_domain}...")
    
    # Try to get compute capacity report
    command = [
        "oci", "compute", "compute-capacity-report", "create-compute-capacity-report",
        "--availability-domain", availability_domain,
        "--compartment-id", compartment_id,
        "--shape-availabilities",
        json.dumps([{
            "instance-shape": "VM.Standard.A1.Flex",
            "instance-shape-config": {
                "ocpus": 1.0,
                "memory-in-gbs": 6.0
            }
        }])
    ]
    
    result = run_oci_command(command)
    
    if result and "data" in result:
        shape_availabilities = result["data"].get("shape-availabilities", [])
        for shape in shape_availabilities:
            if shape.get("instance-shape") == "VM.Standard.A1.Flex":
                availability_status = shape.get("availability-status")
                log(f"Ampere A1 status: {availability_status}")
                return availability_status == "AVAILABLE"
    
    return False


def check_micro_availability(compartment_id: str, availability_domain: str) -> bool:
    """
    Check if VM.Standard.E2.1.Micro instances can be launched
    
    Returns True if capacity is available, False otherwise
    """
    log(f"Checking VM.Standard.E2.1.Micro availability in {availability_domain}...")
    
    command = [
        "oci", "compute", "compute-capacity-report", "create-compute-capacity-report",
        "--availability-domain", availability_domain,
        "--compartment-id", compartment_id,
        "--shape-availabilities",
        json.dumps([{
            "instance-shape": "VM.Standard.E2.1.Micro"
        }])
    ]
    
    result = run_oci_command(command)
    
    if result and "data" in result:
        shape_availabilities = result["data"].get("shape-availabilities", [])
        for shape in shape_availabilities:
            if shape.get("instance-shape") == "VM.Standard.E2.1.Micro":
                availability_status = shape.get("availability-status")
                log(f"E2.1.Micro status: {availability_status}")
                return availability_status == "AVAILABLE"
    
    return False


def get_availability_domains(compartment_id: str) -> List[str]:
    """Get list of availability domains"""
    log("Fetching availability domains...")
    
    command = [
        "oci", "iam", "availability-domain", "list",
        "--compartment-id", compartment_id
    ]
    
    result = run_oci_command(command)
    
    if result and "data" in result:
        domains = [ad["name"] for ad in result["data"]]
        log(f"Found {len(domains)} availability domains")
        return domains
    
    return []


def get_tenancy_id() -> str:
    """Get tenancy OCID from OCI config"""
    try:
        result = subprocess.run(
            ["oci", "iam", "region", "list"],
            capture_output=True,
            text=True,
            check=True
        )
        # If this works, get the actual tenancy
        config_result = subprocess.run(
            ["oci", "setup", "config"],
            capture_output=True,
            text=True
        )
        
        # Try to read from config file
        with open("/Users/giovanni/.oci/config", "r") as f:
            for line in f:
                if line.startswith("tenancy="):
                    return line.split("=")[1].strip()
    except Exception as e:
        log(f"Error getting tenancy ID: {e}")
    
    return ""


def main():
    """Main execution function"""
    log("=" * 60)
    log("OCI Free Tier Availability Checker")
    log("=" * 60)
    
    # Get tenancy/compartment ID (you need to set this)
    compartment_id = get_tenancy_id()
    
    if not compartment_id:
        log("ERROR: Could not determine compartment/tenancy ID")
        log("Please ensure OCI CLI is configured: oci setup config")
        sys.exit(1)
    
    log(f"Using compartment: {compartment_id}")
    
    # Get availability domains
    availability_domains = get_availability_domains(compartment_id)
    
    if not availability_domains:
        log("ERROR: Could not fetch availability domains")
        sys.exit(1)
    
    # Check availability in each domain
    ampere_available = False
    micro_available = False
    
    for ad in availability_domains:
        log(f"\nChecking availability domain: {ad}")
        
        if check_ampere_availability(compartment_id, ad):
            ampere_available = True
            log("✓ Ampere A1 instances are AVAILABLE!")
        
        if check_micro_availability(compartment_id, ad):
            micro_available = True
            log("✓ VM.Standard.E2.1.Micro instances are AVAILABLE!")
    
    # Summary
    log("\n" + "=" * 60)
    log("SUMMARY")
    log("=" * 60)
    log(f"Ampere A1 (ARM): {'AVAILABLE ✓' if ampere_available else 'NOT AVAILABLE ✗'}")
    log(f"E2.1.Micro (AMD): {'AVAILABLE ✓' if micro_available else 'NOT AVAILABLE ✗'}")
    
    # Exit code: 0 if any capacity available, 1 otherwise
    sys.exit(0 if (ampere_available or micro_available) else 1)


if __name__ == "__main__":
    main()
