FROM fnproject/python:3.11-dev as build-stage
WORKDIR /function
ADD requirements.txt /function/
RUN pip3 install --target /python/ --no-cache --no-cache-dir -r requirements.txt && \
    rm -fr ~/.cache/pip /tmp/* requirements.txt func.yaml Dockerfile .venv && \
    chmod -R o+r /python

FROM fnproject/python:3.11
WORKDIR /function
COPY --from=build-stage /python /python
COPY func.py /function/
RUN chmod -R o+r /function
ENV PYTHONPATH=/function:/python
ENTRYPOINT ["/python/bin/fdk", "/function/func.py", "handler"]
