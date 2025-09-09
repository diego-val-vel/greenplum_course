import os, json, random, uuid
from datetime import datetime, timezone
from flask import Flask, jsonify
from confluent_kafka import Producer

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "kafka:9092")
TOPIC = os.getenv("TOPIC", "ventas_inbox")
DEFAULT_BATCH = int(os.getenv("BATCH_SIZE", "5000"))

app = Flask(__name__)
producer = Producer({"bootstrap.servers": KAFKA_BOOTSTRAP})

def _delivery(err, msg):
    if err:
        print(f"[producer][ERROR] {err}")
    else:
        print(f"[producer] Delivered to {msg.topic()} [{msg.partition()}]")

def gen_record():
    return {
        "ts": datetime.now(timezone.utc).isoformat(),
        "id_cliente": random.randint(1, 1_000_000),
        "monto": round(random.uniform(1.0, 5000.0), 2),
        "canal": random.choice(["web", "movil", "tienda"]),
        "order_id": str(uuid.uuid4())
    }

@app.post("/oltp")
def oltp():
    rec = gen_record()
    producer.produce(TOPIC, json.dumps(rec).encode("utf-8"), callback=_delivery)
    producer.flush()
    return jsonify({"status": "ok", "mode": "fila-a-fila", "record": rec})

@app.post("/microbatch")
def microbatch():
    n = DEFAULT_BATCH
    for _ in range(n):
        rec = gen_record()
        producer.produce(TOPIC, json.dumps(rec).encode("utf-8"), callback=_delivery)
    producer.flush()
    return jsonify({"status": "ok", "mode": "microbatch", "rows": n})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
