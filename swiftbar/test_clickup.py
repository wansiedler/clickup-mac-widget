"""Offline tests for the SwiftBar plugin: bucketing and menu rendering."""

import datetime as dt
import importlib.util
import pathlib

_spec = importlib.util.spec_from_file_location("clickup", pathlib.Path(__file__).with_name("clickup.5m.py"))
assert _spec and _spec.loader
cu = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cu)

NOW = dt.datetime(2026, 10, 13, 15, 0)


def ms(d: dt.datetime) -> str:
    return str(int(d.timestamp() * 1000))


def task(tid, name, due=None, prio=None):
    return {
        "id": tid,
        "name": name,
        "url": f"https://app.clickup.com/t/{tid}",
        "due_date": ms(due) if due else None,
        "priority": {"priority": prio} if prio else None,
        "status": {"status": "in progress"},
        "list": {"name": "Sprint"},
    }


TASKS = [
    task("a", "yesterday", NOW - dt.timedelta(days=1)),
    task("b", "this morning", NOW.replace(hour=9)),  # earlier today is "today", not overdue
    task("c", "tonight urgent", NOW.replace(hour=23), "urgent"),
    task("d", "next week", NOW + dt.timedelta(days=7)),
    task("e", "pipe | name"),
]


def test_bucket():
    b = cu.bucket(TASKS, NOW)
    assert [t["id"] for t in b["overdue"]] == ["a"]
    assert [t["id"] for t in b["today"]] == ["b", "c"]
    assert [t["id"] for t in b["upcoming"]] == ["d"]
    assert [t["id"] for t in b["nodate"]] == ["e"]


def test_render_title_and_escaping():
    timer = {"id": "t1", "start": ms(NOW - dt.timedelta(minutes=83)), "task": {"id": "b", "name": "this morning"}}
    lines = cu.render(cu.bucket(TASKS, NOW), timer, NOW, "/p/clickup.5m.py")
    assert lines[0].startswith("1:23 · 3 | sfimage=timer color=")
    assert any(line.startswith('Stop timer | shell="/p/clickup.5m.py" param1=stop') for line in lines)
    assert "--pipe ¦ name | href=https://app.clickup.com/t/e" in lines


def test_render_nothing_due():
    lines = cu.render(cu.bucket([], NOW), None, NOW, "/p")
    assert lines[0] == "0 | sfimage=checklist"
    assert "Nothing due today" in lines
