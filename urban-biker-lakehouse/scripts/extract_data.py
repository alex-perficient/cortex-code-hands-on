# Script de Python para pegarle a la API (GBFS)

import requests
import pandas as pd
import json
from datetime import datetime, timezone
import snowflake.connector
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
        # 2. Guardar localmente como temporal para luego subir a Snowflake
        filename = f"bikes_{network_id}_{datetime.now().strftime('%Y%m%d_%H%M')}.parquet"
        df_bikes.to_parquet(filename, index=False)
        print(f"Archivo guardado exitosamente: {filename}")
        
        # 3. Subir a AWS S3
        def upload_to_s3(file_path):
            bucket_name = os.getenv("AWS_S3_BUCKET_NAME")
            if not bucket_name:
                print("⚠️ AWS_S3_BUCKET_NAME no está definido en el .env. Saltando subida a nube.")
                return
            
            # boto3 busca automaticamente AWS_ACCESS_KEY_ID y AWS_SECRET_ACCESS_KEY del .env (load_dotenv)
            print(f"Subiendo {file_path} a AWS S3 (s3://{bucket_name}/citybikes_parquet/)...")
            try:
                s3_client = boto3.client('s3')
                object_name = f"citybikes_parquet/{os.path.basename(file_path)}"
                
                s3_client.upload_file(file_path, bucket_name, object_name)
                print(f"✅ ¡Archivo exitosamente almacenado en AWS: s3://{bucket_name}/{object_name}!")
            except Exception as e:
                print(f"❌ Falló al subir a AWS S3: {e}")
                
        upload_to_s3(filename)
    
    
