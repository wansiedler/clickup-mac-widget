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


def task(tid, name, due=None, prio=None, parent=None, custom_id=None):
    return {
        "id": tid,
        "parent": parent,
        "custom_id": custom_id,
        "name": name,
        "url": f"https://app.clickup.com/t/{tid}",
        "due_date": ms(due) if due else None,
        "priority": {"priority": prio} if prio else None,
        "status": {"status": "in progress", "color": "#3e63dd"},
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
    assert [r[0]["id"] for r in b["overdue"]] == ["a"]
    assert [r[0]["id"] for r in b["today"]] == ["b", "c"]
    assert [r[0]["id"] for r in b["upcoming"]] == ["d"]
    assert [r[0]["id"] for r in b["nodate"]] == ["e"]


def test_nesting():
    tasks = [
        task("p", "parent", NOW.replace(hour=10)),
        task("k1", "child", NOW.replace(hour=9), parent="p"),
        task("k2", "grandchild", NOW.replace(hour=11), parent="k1"),
        task("o", "orphan", NOW.replace(hour=12), parent="x"),
        task("u", "child elsewhere", NOW + dt.timedelta(days=2), parent="p"),
    ]
    b = cu.bucket(tasks, NOW, {"x": "Epic"})
    # child sorts before its parent by due date, but is placed under it
    assert [(r[0]["id"], r[1], r[2]) for r in b["today"]] == [
        ("p", 0, None), ("k1", 1, None), ("k2", 2, None), ("o", 0, "Epic"),
    ]
    assert [(r[0]["id"], r[1], r[2]) for r in b["upcoming"]] == [("u", 0, "parent")]
    lines = cu.render(b, None, NOW, "/p")
    assert "  ↳ #k1  child | href=https://app.clickup.com/t/k1 color=#3e63dd trim=false" in lines
    assert "#o  Epic › orphan | href=https://app.clickup.com/t/o color=#3e63dd" in lines


def test_custom_id():
    rows = cu.bucket([task("z", "named", custom_id="DEV-42")], NOW)["nodate"]
    assert cu.task_lines(rows[0], "")[0].startswith("DEV-42  named | ")


def test_render_title_and_escaping():
    timer = {"id": "t1", "start": ms(NOW - dt.timedelta(minutes=83)), "task": {"id": "b", "name": "this morning"}}
    lines = cu.render(cu.bucket(TASKS, NOW), timer, NOW, "/p/clickup.5m.py")
    assert lines[0].startswith("1:23 · 3 | sfimage=timer color=")
    assert any(line.startswith('Stop timer | shell="/p/clickup.5m.py" param1=stop') for line in lines)
    assert "--#e  pipe ¦ name | href=https://app.clickup.com/t/e color=#3e63dd" in lines


def test_render_nothing_due():
    lines = cu.render(cu.bucket([], NOW), None, NOW, "/p")
    assert lines[0] == "0 | sfimage=checklist"
    assert "Nothing due today" in lines
