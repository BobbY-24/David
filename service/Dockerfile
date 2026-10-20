FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY david_lab ./david_lab

ENV PYTHONUNBUFFERED=1
EXPOSE 43124
CMD ["uvicorn", "david_lab.api:app", "--host", "0.0.0.0", "--port", "43124"]
