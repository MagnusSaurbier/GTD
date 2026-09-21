from frontmatter import read_note, write_note


def test_round_trip_unchanged_file_is_byte_identical():
    text = (
        "---\n"
        "status: next\n"
        "contexts: [mac]\n"
        "# a comment the app doesn't know about\n"
        "custom: some value\n"
        "---\n"
        "# Why?\n"
        "Body text.\n"
    )
    fm, body = read_note(text)
    assert write_note(fm, body) == text


def test_editing_one_key_leaves_others_untouched():
    text = (
        "---\n"
        "status: to-do\n"
        "# keep me\n"
        "custom: unchanged\n"
        "contexts: [Phone, Home]\n"
        "---\n"
        "body\n"
    )
    fm, body = read_note(text)
    fm.set_scalar("status", "backlog")
    out = write_note(fm, body)
    assert "status: backlog" in out
    assert "# keep me" in out
    assert "custom: unchanged" in out
    assert "contexts: [Phone, Home]" in out


def test_get_list_flow_style():
    fm, _ = read_note("---\ncontexts: [Phone, Home, live]\n---\n")
    assert fm.get_list("contexts") == ["Phone", "Home", "live"]


def test_get_list_block_style():
    fm, _ = read_note("---\ncontexts:\n  - Phone\n  - Home\n---\n")
    assert fm.get_list("contexts") == ["Phone", "Home"]


def test_set_list_preserves_block_style():
    fm, body = read_note("---\ncontexts:\n  - Phone\n---\n")
    fm.set_list("contexts", ["phone"])
    out = write_note(fm, body)
    assert "contexts:\n  - phone" in out
    assert "[phone]" not in out


def test_set_list_defaults_to_flow_style_for_new_key():
    fm, body = read_note("---\nstatus: next\n---\n")
    fm.set_list("contexts", ["mac", "phone"])
    out = write_note(fm, body)
    assert "contexts: [mac, phone]" in out


def test_remove_key_drops_only_that_line():
    fm, body = read_note("---\npriority: high\nstatus: next\n---\nbody\n")
    fm.remove("priority")
    out = write_note(fm, body)
    assert "priority" not in out
    assert "status: next" in out


def test_remove_missing_key_is_a_no_op():
    fm, body = read_note("---\nstatus: next\n---\nbody\n")
    assert fm.remove("nope") is False


def test_set_scalar_adds_new_key_at_end():
    fm, body = read_note("---\nstatus: waiting\n---\nbody\n")
    fm.set_scalar("reviewReason", "migrated")
    out = write_note(fm, body)
    lines = out.split("\n")
    assert lines[1] == "status: waiting"
    assert lines[2] == "reviewReason: migrated"


def test_set_scalar_none_writes_bare_empty_key():
    fm, body = read_note("---\nstatus: waiting\n---\nbody\n")
    fm.set_scalar("waitingFor", None)
    out = write_note(fm, body)
    assert "waitingFor:" in out
    assert fm.get_scalar("waitingFor") is None


def test_scalar_needing_quotes_is_quoted():
    fm, body = read_note("---\nstatus: waiting\n---\nbody\n")
    fm.set_scalar("reviewReason", "a value: with a colon")
    out = write_note(fm, body)
    assert 'reviewReason: "a value: with a colon"' in out
    fm2, _ = read_note(out)
    assert fm2.get_scalar("reviewReason") == "a value: with a colon"


def test_read_note_returns_none_without_frontmatter():
    assert read_note("just a plain markdown file\n") is None


def test_body_with_embedded_delimiter_like_lines_is_preserved():
    text = "---\nstatus: next\n---\nSee ---\nmore text\n"
    fm, body = read_note(text)
    assert body == "See ---\nmore text\n"
    assert write_note(fm, body) == text
