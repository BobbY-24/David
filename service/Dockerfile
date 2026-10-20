FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY fieldline_lab ./fieldline_lab

ENV PYTHONUNBUFFERED=1
EXPOSE 43124
CMD ["uvicorn", "fieldline_lab.api:app", "--host", "0.0.0.0", "--port", "43124"]
