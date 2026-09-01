#!/usr/bin/env python3
"""Create a text-only compatibility copy of Ollama's older gemma3:4b GGUF.

This utility is preserved with the round-two evidence. It does not modify the
source GGUF. It requires the `gguf-py` package from the matching llama.cpp
checkout and NumPy. Read ROUND2_RESULTS.md and ROUND2_PROTOCOL.md first: the
patched Vulkan run still produced a recoverable GPU device-loss failure.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / 'llama.cpp' / 'gguf-py'))
import numpy as np  # noqa: E402
import gguf  # noqa: E402


if len(sys.argv) != 3:
    raise SystemExit(f'usage: {Path(sys.argv[0]).name} SOURCE.gguf OUTPUT.gguf')

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
epsilon_key = 'gemma3.attention.layer_norm_rms_epsilon'

if not src.is_file():
    raise SystemExit(f'source GGUF is not a readable file: {src}')
if src.resolve() == dst.resolve():
    raise SystemExit('source and output paths must be different')
if dst.exists():
    raise SystemExit(f'refusing to overwrite existing output: {dst}')
if not dst.parent.is_dir():
    raise SystemExit(f'output directory does not exist: {dst.parent}')

reader = gguf.GGUFReader(str(src))
architecture = reader.get_field(gguf.Keys.General.ARCHITECTURE).contents()

try:
    writer = gguf.GGUFWriter(str(dst), arch=architecture, endianess=reader.endianess)
except TypeError:
    writer = gguf.GGUFWriter(str(dst), arch=architecture)

for field in reader.fields.values():
    if field.name == gguf.Keys.General.ARCHITECTURE or field.name.startswith('GGUF.'):
        continue
    value_type = field.types[0]
    subtype = field.types[-1] if value_type == gguf.GGUFValueType.ARRAY else None
    value = field.contents()
    if value is not None:
        writer.add_key_value(field.name, value, value_type, sub_type=subtype)

writer.add_key_value(epsilon_key, 1e-6, gguf.GGUFValueType.FLOAT32)

# token_embd.weight is Q6_K with 2,560 values per row: ten 210-byte blocks.
zero_row = np.zeros(2100, dtype=np.uint8)
tensors = []
skipped = 0

for tensor in reader.tensors:
    if tensor.name.startswith(('v.', 'mm.')):
        skipped += 1
        continue
    data = tensor.data
    if tensor.name == 'token_embd.weight':
        if data.ndim != 2 or data.shape[1] != zero_row.size:
            raise RuntimeError(f'unexpected token_embd.weight shape: {data.shape}')
        data = np.concatenate([data, zero_row.reshape(1, -1)], axis=0)
    tensors.append((tensor.name, data, tensor.tensor_type))
    writer.add_tensor_info(tensor.name, data.shape, data.dtype, data.nbytes, tensor.tensor_type)

writer.write_header_to_file()
writer.write_kv_data_to_file()
writer.write_ti_data_to_file()
for _, data, _ in tensors:
    writer.write_tensor_data(data, tensor_endianess=reader.endianess)
writer.close()

print(f'Wrote {dst}; added {epsilon_key}, padded vocabulary, removed {skipped} vision/projector tensors.')
