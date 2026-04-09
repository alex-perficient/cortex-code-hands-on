import os
import snowflake.connector
from dotenv import load_dotenv

load_dotenv()

def load_data_from_stage():
    """
    Se conecta a Snowflake y ejecuta el comando COPY INTO para cargar 
    los datos desde el Stage externo en AWS S3 hacia la tabla BIKE_STATIONS_RAW.
    """
    # 1. Obtener credenciales de Snowflake del archivo .env
    user = os.getenv("SNOWFLAKE_USER")
    password = os.getenv("SNOWFLAKE_PASSWORD")
    account = os.getenv("SNOWFLAKE_ACCOUNT")
    
    # Valores por defecto que vimos en el archivo setup_snowflake.sql,
    # aunque también pueden pasarse como variables de entorno.
    warehouse = os.getenv("SNOWFLAKE_WAREHOUSE", "COMPUTE_WH") 
    database = os.getenv("SNOWFLAKE_DATABASE", "URBAN_BIKER_DB_33")
    schema = os.getenv("SNOWFLAKE_SCHEMA", "RAW")
    role = os.getenv("SNOWFLAKE_ROLE", "COCO_HOL_RL")
    
    if not all([user, password, account]):
        print("⚠️ Faltan credenciales de Snowflake en tu archivo .env (SNOWFLAKE_USER, SNOWFLAKE_PASSWORD, SNOWFLAKE_ACCOUNT).")
        print("Por favor, agrégalas antes de ejecutar el script.")
        return
        
    print(f"Conectando a Snowflake (Account: {account}, User: {user})...")
    
    try:
        # 2. Conectar a Snowflake
        conn = snowflake.connector.connect(
            user=user,
            password=password,
            account=account,
            warehouse=warehouse,
            database=database,
            schema=schema,
            role=role
        )
        
        cursor = conn.cursor()
        
        # 3. Asegurar usar el entorno correcto
        print(f"Usando DB: {database}, Schema: {schema}, Role: {role}")
        cursor.execute(f"USE ROLE {role}")
        cursor.execute(f"USE DATABASE {database}")
        cursor.execute(f"USE SCHEMA {schema}")
        
        # 4. Comando COPY INTO
        # Hacemos referencia al stage de S3: @BIKE_STAGE_S3
        sql_command = """
        COPY INTO BIKE_STATIONS_RAW (raw_data, filename)
        FROM (
            SELECT $1, METADATA$FILENAME
            FROM @BIKE_STAGE_S3
        )
        FILE_FORMAT = (TYPE = 'PARQUET');
        """
        
        print("Ejecutando comando COPY INTO desde S3 hacia Snowflake...")
        cursor.execute(sql_command)
        
        # 5. Obtener e imprimir el resultado de la carga
        result = cursor.fetchall()
        print("✅ Carga finalizada existosamente. Resultado:")
        for row in result:
            print(f" - {row}")
            
    except snowflake.connector.errors.ProgrammingError as e:
        print(f"❌ Error de SQL en Snowflake: {e}")
    except Exception as e:
        print(f"❌ Error general: {e}")
    finally:
        # Cerrar siempre la conexión
        if 'cursor' in locals():
            cursor.close()
        if 'conn' in locals():
            conn.close()

if __name__ == "__main__":
    load_data_from_stage()
