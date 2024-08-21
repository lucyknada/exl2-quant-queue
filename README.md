# exl2-quant-queue

since a few people asked me for my exl2 queue script, I'm publishing it; I do not intend to add features or other things that are irrelevant to my personal use-case, but you're free to use it if you want.

the script will automatically prefix the README.md with a header symbolizing it's a quant, add the measurement.json file to the main branch and then upload every quant automatically into its own branch, it also checks if a BPW upload already exists, and skips past that; further if a measurement file already exists, it'll use that from the last run automatically too.

a few things this assumes:
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
