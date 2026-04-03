"""Telvm certified lab: FastAPI + uvicorn. GET / -> JSON 200 on port 3333."""

from fastapi import FastAPI
from fastapi.responses import JSONResponse

app = FastAPI()


@app.get("/")
def probe():
    return JSONResponse(
        {"status": "ok", "service": "telvm-lab", "probe": "/"}
    )
