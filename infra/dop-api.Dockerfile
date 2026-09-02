# A skeleton — the dop-api image (Python). To be finalized with dop-api's stack.
# An example (TODO: adjust it to the chosen stack):
FROM python:3.11-slim
WORKDIR /app
# COPY pyproject.toml ./
# RUN pip install --no-cache-dir .
# COPY . .
# EXPOSE 8787
# CMD ["python", "-m", "dop_api"]
CMD ["python", "-c", "print('dop-api: a skeleton — define the stack')"]
