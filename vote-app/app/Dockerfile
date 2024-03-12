FROM python:slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV MONGO_ROOT_USERNAME=#username
ENV MONGO_ROOT_PASSWORD=#password
ENV MONGO_IP=#ip 
ENV MONGO_DATABASE=#database

EXPOSE 5000

CMD ["python", "app.py"]