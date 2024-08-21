# exl2-quant-queue

since a few people asked me for my exl2 queue script, I'm publishing it; I do not intend to add features or other things that are irrelevant to my personal use-case, but you're free to use it if you want.

this script automatically handles:
- prefixing the original README.md with a small note that this is a quant
- uploads the quant as private so you can check if everything is fine first
- uploads each BPW as its own branch and uploads measurement.json to the main branch
- checks if a BPW already exists on your huggingface and skips over it
- re-uses measurement.json if one already was done in the processed folder
- auto deletes .bin and .pth files, since lots of times people love to include those and that just explodes the upload size
- converts .bin files to safetensor if the target model is in .bin only
- if there's an external measurement file, just wait till it starts the measurement pass, kill the process, add the measurement file into the output folder of that model and restart, it'll pick it up from there.

a few things this assumes:
- there's a venv in the exllama folder called "venv" (`python -m venv venv`)
- huggingface-cli and hf_transfer are installed (`pip install "huggingface_hub[cli]" hf_transfer`)
- you git cloned https://github.com/turboderp/exllamav2
- you installed all the dependencies via `pip install -r requirements.txt`
- you either installed an appropriate wheel for your cuda+python+torch version from exl2 releasepage e.g. `pip install https://github.com/turboderp/exllamav2/releases/download/v0.1.8/exllamav2-0.1.8+cu121.torch2.2.2-cp310-cp310-linux_x86_64.whl` or you built it directly with `pip install .` (requires nvcc and appropriate gcc versions etc, I prefer the former)
- you dropped quant_queue.sh inside the exllamav2 folder
- you changed USER and HFTOKEN variable inside quant_queue.sh
- you created a queue.txt alongside it

queue.txt example:
```
https://huggingface.co/HuggingFaceTB/SmolLM-1.7B-Instruct/3.0
https://huggingface.co/HuggingFaceTB/SmolLM-1.7B-Instruct/4.0
https://huggingface.co/HuggingFaceTB/SmolLM-1.7B-Instruct/6.0
https://huggingface.co/microsoft/Phi-3.5-mini-instruct/3.0
https://huggingface.co/microsoft/Phi-3.5-mini-instruct/4.0
https://huggingface.co/microsoft/Phi-3.5-mini-instruct/6.0
```
basically you just put the URLs and the desired BPW at the end of the URL, it'll auto-abort along the way if there's errors. (feel free to adjust that behavior, I will not do that for you)



that's it, have fun with it!
