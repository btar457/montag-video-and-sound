from studio.voiceover import split_lines


def test_split_lines_snaps_to_nearby_pauses():
    lines = ["aaaa", "aaaa", "aaaaaaaa"]  # estimates at 2.5 and 5.0 of 10 s
    bounds = split_lines(lines, 10.0, pause_mids=[2.8, 5.6, 9.5])
    assert bounds == [0.0, 2.8, 5.6, 10.0]


def test_split_lines_ignores_far_pauses():
    bounds = split_lines(["aa", "aa"], 10.0, pause_mids=[9.0])
    assert bounds == [0.0, 5.0, 10.0]


def test_single_line_section():
    assert split_lines(["كل قطعة بيها روح"], 5.9, []) == [0.0, 5.9]


def test_boundaries_never_collapse_onto_one_pause():
    # Estimates at 2.0 and 2.6 s, one pause at 2.3 s: only one may use it.
    bounds = split_lines(["a" * 20, "a" * 6, "a" * 74], 10.0, pause_mids=[2.3])
    assert bounds == sorted(bounds)
    assert all(b - a >= 0.3 for a, b in zip(bounds, bounds[1:]))
    assert bounds.count(2.3) == 1


def test_boundaries_keep_room_for_later_lines():
    bounds = split_lines(["a" * 98, "a", "a"], 3.0, pause_mids=[])
    assert all(b - a >= 0.3 - 1e-9 for a, b in zip(bounds, bounds[1:]))
    assert bounds[-1] == 3.0
