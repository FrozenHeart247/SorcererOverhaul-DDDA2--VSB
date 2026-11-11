"""Read minidump exception/module addresses without executing or uploading the dump.

Stack entries below are raw pointer candidates, not a debugger-unwound call stack.
"""
import argparse
import datetime
import json
import struct
from pathlib import Path


def inspect(path):
    data = Path(path).read_bytes()
    if data[:4] != b"MDMP":
        raise ValueError("Not a Windows minidump")
    def unpack(fmt, at):
        return struct.unpack_from("<" + fmt, data, at)
    def string(at):
        size, = unpack("I", at)
        return data[at + 4:at + 4 + size].decode("utf-16-le", errors="replace")
    count, directory = unpack("II", 8)
    timestamp, = unpack("I", 20)
    streams = {}
    for i in range(count):
        kind, size, rva = unpack("III", directory + i * 12)
        streams[kind] = (rva, size)
    modules = []
    if 4 in streams:
        rva, _ = streams[4]
        n, = unpack("I", rva)
        for i in range(n):
            at = rva + 4 + i * 108
            base, size, checksum, stamp, name = unpack("QIIII", at)
            modules.append({"name": string(name).replace("\\", "/").rsplit("/", 1)[-1],
                            "base": base, "size": size})
    def address(value):
        item = {"address": hex(value)}
        for module in modules:
            if module["base"] <= value < module["base"] + module["size"]:
                item.update(module=module["name"], offset=hex(value - module["base"]))
                break
        return item
    result = {"dump": str(path), "created_utc": datetime.datetime.fromtimestamp(
        timestamp, datetime.timezone.utc).isoformat(), "modules": [
            {**m, "base": hex(m["base"]), "size": hex(m["size"])} for m in modules]}
    if 6 not in streams:
        return result
    rva, _ = streams[6]
    tid, = unpack("I", rva)
    code, flags = unpack("II", rva + 8)
    rip, = unpack("Q", rva + 24)
    n, = unpack("I", rva + 32)
    params = unpack("15Q", rva + 40)
    ctx_size, ctx = unpack("II", rva + 160)
    result["exception"] = {"thread_id": tid, "code": hex(code), "flags": hex(flags),
                           **address(rip), "parameters": [hex(v) for v in params[:n]]}
    # AMD64 CONTEXT: integer registers begin at offset 120; RIP is at offset 248.
    if ctx_size >= 256:
        names = ("rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi",
                 "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip")
        registers = dict(zip(names, unpack("17Q", ctx + 120)))
        result["registers"] = {k: address(v) for k, v in registers.items()}
        if 3 in streams:
            trva, _ = streams[3]
            threads, = unpack("I", trva)
            for i in range(threads):
                at = trva + 4 + 48 * i
                thread_id, = unpack("I", at)
                if thread_id != tid:
                    continue
                stack_start, stack_size, stack_rva = unpack("QII", at + 24)
                start = max(0, registers["rsp"] - stack_start)
                candidates = []
                for off in range(start, min(stack_size - 7, start + 8192), 8):
                    value, = unpack("Q", stack_rva + off)
                    mapped = address(value)
                    if "module" in mapped:
                        candidates.append({"stack_offset": hex(off - start), **mapped})
                result["raw_stack_pointer_candidates_not_unwound"] = candidates
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dump")
    parser.add_argument("--output")
    args = parser.parse_args()
    result = inspect(args.dump)
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).write_text(text + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "modules"}, indent=2))
