import os
from typing import Any, Dict, List

from iii import InitOptions, Logger, register_worker

iii = register_worker(
    os.environ.get("III_URL", "ws://localhost:49134"),
    InitOptions(worker_name="math-worker"),
)
logger = Logger()

# ---------------------------------------------------------------------------
# PRODUCTION NOTE:
#   Real inference uses transformers + GGUF model (gemma-3-270m-Q8_0.gguf).
#   Requires t3.xlarge (16 GB RAM, 4 vCPU) to load the model into memory.
#   For the Free Tier demo, a mock response is returned instead.
#
#   To enable real inference:
#     1. Deploy on t3.xlarge
#     2. Uncomment the block below and remove the mock return
# ---------------------------------------------------------------------------

# REAL INFERENCE (uncomment on t3.xlarge):
# from transformers import AutoModelForCausalLM, AutoTokenizer
# model_id  = "ggml-org/gemma-3-270m-GGUF"
# gguf_file = "gemma-3-270m-Q8_0.gguf"
# tokenizer = AutoTokenizer.from_pretrained(model_id, gguf_file=gguf_file)
# model     = AutoModelForCausalLM.from_pretrained(model_id, gguf_file=gguf_file)


def run_inference_handler(payload: Dict[str, str | List[Dict[str, Any]]]) -> Dict[str, Any]:
    messages = payload.get("messages", [])
    last_message = messages[-1].get("content", "") if messages else ""

    logger.info(f"inference::run_inference called with {len(messages)} messages")

    # --- MOCK response (Free Tier demo) ---
    result = (
        f"[MOCK RESPONSE] Received: '{last_message}'. "
        "Deploy on t3.xlarge to enable real Gemma-3 inference."
    )

    # --- REAL inference (uncomment on t3.xlarge) ---
    # text   = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    # inputs = tokenizer(text, return_tensors="pt").to(model.device)
    # output = model.generate(**inputs, max_new_tokens=32000)
    # result = tokenizer.decode(output[0][inputs["input_ids"].shape[-1]:], skip_special_tokens=True)

    return result


iii.register_function("inference::run_inference", run_inference_handler)
print("Inference worker started - listening for calls")
