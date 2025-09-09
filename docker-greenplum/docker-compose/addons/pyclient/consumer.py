import os, json, time
import psycopg2
from kafka import KafkaConsumer

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "kafka:9092")
TOPIC = os.getenv("TOPIC", "ventas_inbox")

GP_HOST = os.getenv("GP_HOST", "master")
GP_PORT = int(os.getenv("GP_PORT", "5432"))
GP_DB = os.getenv("GP_DB", "lab_gp7")
GP_USER = os.getenv("GP_USER", "gpadmin")
GP_PASS = os.getenv("GP_PASS", "gparray")

MODE = os.getenv("MODE", "row")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "1000"))
BATCH_TIMEOUT_SEC = int(os.getenv("BATCH_TIMEOUT_SEC", "3"))

print(f"[consumer] Connected to Kafka {KAFKA_BOOTSTRAP}, topic={TOPIC}, mode={MODE}")

consumer = KafkaConsumer(
    TOPIC,
    bootstrap_servers=[KAFKA_BOOTSTRAP],
    value_deserializer=lambda m: json.loads(m.decode("utf-8")),
    auto_offset_reset="earliest",
    enable_auto_commit=True,
)

conn = psycopg2.connect(
    host=GP_HOST, port=GP_PORT, dbname=GP_DB, user=GP_USER, password=GP_PASS
)
conn.autocommit = True
cur = conn.cursor()
print(f"[consumer] Connected to GPDB {GP_HOST}:{GP_PORT}/{GP_DB}")

buffer = []
last_flush = time.time()

def flush_if_needed(force=False):
    global buffer, last_flush
    if MODE == "microbatch" and (force or len(buffer) >= BATCH_SIZE or (time.time() - last_flush) >= BATCH_TIMEOUT_SEC):
        if buffer:
            cur.executemany(
                "INSERT INTO ventas (ts,id_cliente,monto,canal,order_id) VALUES (%s,%s,%s,%s,%s)",
                buffer,
            )
            print(f"[consumer][INSERT] {len(buffer)} rows inserted")
            buffer.clear()
            last_flush = time.time()

try:
    for msg in consumer:
        try:
            rec = msg.value
            ts = rec["ts"]
            id_cliente = rec["id_cliente"]
            monto = rec["monto"]
            canal = rec["canal"]
            order_id = int(time.time() * 1000)

            if MODE == "row":
                cur.execute(
                    "INSERT INTO ventas (ts,id_cliente,monto,canal,order_id) VALUES (%s,%s,%s,%s,%s)",
                    (ts, id_cliente, monto, canal, order_id),
                )
                print("[consumer][INSERT] 1 row inserted")
            else:
                buffer.append((ts, id_cliente, monto, canal, order_id))
                flush_if_needed(False)
        except Exception as e:
            print(f"[consumer][ERROR] {e}")
except KeyboardInterrupt:
    pass
finally:
    flush_if_needed(True)
    cur.close()
    conn.close()
