# Esqueleto — imagem da dop-api (Python). A ser finalizado com a stack do dop-api.
# Exemplo (TODO: ajustar à stack escolhida):
FROM python:3.11-slim
WORKDIR /app
# COPY pyproject.toml ./
# RUN pip install --no-cache-dir .
# COPY . .
# EXPOSE 8787
# CMD ["python", "-m", "dop_api"]
CMD ["python", "-c", "print('dop-api: esqueleto — defina a stack')"]
