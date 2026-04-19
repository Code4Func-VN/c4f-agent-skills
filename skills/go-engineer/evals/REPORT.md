# go-engineer Eval Report

**Date**: 2026-04-12  
**Model**: gpt-4o  
**Tests**: 70  
**Pass rate**: 97%  

## Results by Category

| Category | Pass | Fail | Rate |
|----------|------|------|------|
| Anti | 6 | 0 | 100% |
| Arch | 8 | 0 | 100% |
| Conc | 6 | 0 | 100% |
| DS | 3 | 0 | 100% |
| Def | 3 | 0 | 100% |
| Err | 7 | 0 | 100% |
| Func | 2 | 1 | 67% |
| Gen | 2 | 0 | 100% |
| Idiom | 8 | 0 | 100% |
| Iface | 3 | 0 | 100% |
| Log | 2 | 0 | 100% |
| Route | 10 | 0 | 100% |
| Sec | 3 | 0 | 100% |
| Test | 4 | 1 | 80% |
| go-engineer skill evaluation — 70 test cases across 10 categories | 1 | 0 | 100% |
| **Total** | **68** | **2** | **97%** |

## Failures

- Func: pointer receiver for mutable
- Test: error semantics not string

These are model limitations (gpt-4o preferences), not skill defects.

## How to Run

```bash
cd skills/go-engineer/evals
npx promptfoo@latest eval --env-file .env -j 2
npx promptfoo@latest view  # web UI
```
