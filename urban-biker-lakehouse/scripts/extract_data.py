# Script de Python para pegarle a la API (GBFS)

import requests
import pandas as pd
from datetime import datetime, timezone
import os
from dotenv import load_dotenv
import boto3

load_dotenv()

def fetch_citybike_data(network_id="bicimad"):
    url = f"https://api.citybik.es/v2/networks/{network_id}"
    print(f"Extrayendo datos de: {url}...")
    
    response = requests.get(url)
    if response.status_code == 200:
        data = response.json()
        stations = data['network']['stations']
        
        # Convertimos a DataFrame para facilitar la manipulación
        df = pd.json_normalize(stations)
        
        # Añadimos metadata de tiempo de extracción
        df['extraction_at'] = datetime.now(timezone.utc)
        
        return df
    else:
        print(f"Error al conectar: {response.status_code}")
        return None



if __name__ == "__main__":
    # 1. Extraer
    network_id = "bicimad" # Puedes cambiarlo por "citibikenyc" u otro
    df_bikes = fetch_citybike_data(network_id)
    
    if df_bikes is not None:
        # 2. Subir directo a AWS S3 (sin archivo local)
        bucket_name = os.getenv("AWS_S3_BUCKET_NAME")
        if not bucket_name:
            print("AWS_S3_BUCKET_NAME no esta definido en el .env. Saltando subida a nube.")
        else:
            import io
            filename = f"bikes_{network_id}_{datetime.now().strftime('%Y%m%d_%H%M')}.parquet"
            object_name = f"citybikes_parquet/{filename}"
            print(f"Subiendo a AWS S3 (s3://{bucket_name}/{object_name})...")
            try:
                buffer = io.BytesIO()
                df_bikes.to_parquet(buffer, index=False)
                buffer.seek(0)
                s3_client = boto3.client('s3')
                s3_client.upload_fileobj(buffer, bucket_name, object_name)
                print(f"Archivo subido exitosamente: s3://{bucket_name}/{object_name}")
            except Exception as e:
                print(f"Fallo al subir a AWS S3: {e}")

