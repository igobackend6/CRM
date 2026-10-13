from concurrent.futures import ThreadPoolExecutor
from typing import Any, Callable

# Independent database lookups (a call's lead name, its agent, its outcome ...) used to run one after
# another, each waiting on a network round trip to Supabase. Run side by side they cost about as much as
# the slowest one. Supabase closes a connection that carries too many simultaneous requests, so the number
# in flight is capped. Tasks never wait on other pool tasks, so the pool cannot deadlock.
_POOL = ThreadPoolExecutor(max_workers=6, thread_name_prefix="par")


def run_parallel(tasks: list[Callable[[], Any]]) -> list[Any]:
    """Runs the zero-argument callables side by side; results come back in the same order, and the first
    error is raised (as it would have been when run one by one)."""
    futures = [_POOL.submit(t) for t in tasks]
    return [f.result() for f in futures]
