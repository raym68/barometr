"""Расчёты давления для локального HTTP API."""

from __future__ import annotations

import math

GAS_CONSTANT = 287.05
GRAVITY = 9.80665
TEMPERATURE_C = 20.0
SCALE_HEIGHT = GAS_CONSTANT * (TEMPERATURE_C + 273.15) / GRAVITY


def _number(value: object, name: str) -> float:
    if isinstance(value, bool):
        raise ValueError(f"{name}: введите число.")
    try:
        result = float(value)
    except (TypeError, ValueError):
        raise ValueError(f"{name}: введите число.") from None
    if not math.isfinite(result):
        raise ValueError(f"{name}: введите конечное число.")
    return result


def _integer(value: object, name: str, minimum: int = 1, maximum: int = 300) -> int:
    number = _number(value, name)
    if not number.is_integer() or not minimum <= number <= maximum:
        raise ValueError(f"{name}: укажите целое число от {minimum} до {maximum}.")
    return int(number)


def _pressure(value: object, name: str) -> float:
    pressure = _number(value, name)
    if not 300 <= pressure <= 1100:
        raise ValueError(f"{name}: допустимо от 300 до 1100 гПа.")
    return pressure


def pressure_table(data: dict) -> dict:
    step = _number(data.get("step"), "Высота между этажами")
    if not 1 <= step <= 20:
        raise ValueError("Высота между этажами: допустимо от 1 до 20 м.")
    count = _integer(data.get("count"), "Этажей в здании")
    reference_floor = _integer(data.get("referenceFloor"), "Опорный этаж")
    if reference_floor > count:
        raise ValueError("Опорный этаж должен находиться в здании.")
    reference_pressure = _pressure(data.get("referencePressure"), "Опорное давление")
    rows = []
    for floor in range(1, count + 1):
        rows.append({
            "floor": floor,
            "height": (floor - 1) * step,
            "pressure": reference_pressure * math.exp(
                -(floor - reference_floor) * step / SCALE_HEIGHT
            ),
        })
    return {"rows": rows}


def height_from_measurements(data: dict) -> dict:
    items = data.get("measurements")
    if not isinstance(items, list) or not 2 <= len(items) <= 300:
        raise ValueError("Укажите от двух до 300 замеров.")
    readings = []
    for item in items:
        if not isinstance(item, dict):
            raise ValueError("Каждый замер должен содержать этаж и давление.")
        readings.append({
            "floor": _integer(item.get("floor"), "Этаж"),
            "pressure": _pressure(item.get("pressure"), "Давление"),
        })
    readings.sort(key=lambda item: item["floor"])
    if len({item["floor"] for item in readings}) != len(readings):
        raise ValueError("Номера этажей должны различаться.")
    intervals = []
    for lower, upper in zip(readings, readings[1:]):
        if upper["pressure"] >= lower["pressure"]:
            raise ValueError(
                "На верхнем этаже давление должно быть ниже. Проверьте замеры."
            )
        height = SCALE_HEIGHT * math.log(lower["pressure"] / upper["pressure"])
        intervals.append({
            "lowerFloor": lower["floor"],
            "upperFloor": upper["floor"],
            "deltaPressure": lower["pressure"] - upper["pressure"],
            "height": height,
            "perFloor": height / (upper["floor"] - lower["floor"]),
        })
    first, last = readings[0], readings[-1]
    average = SCALE_HEIGHT * math.log(first["pressure"] / last["pressure"]) / (
        last["floor"] - first["floor"]
    )
    return {"intervals": intervals, "averageHeight": average}


def compare_pressure(data: dict) -> dict:
    expected = _pressure(data.get("expectedPressure"), "Расчётное давление")
    measured = _pressure(data.get("measuredPressure"), "Измеренное давление")
    delta = round(measured - expected, 2)
    return {"difference": delta, "direction": "above" if delta > 0 else "below" if delta < 0 else "equal"}


def locate_floor(data: dict) -> dict:
    """Определить ближайший этаж по давлению и текущей опорной точке."""
    step = _number(data.get("step"), "Высота между этажами")
    if not 1 <= step <= 20:
        raise ValueError("Высота между этажами: допустимо от 1 до 20 м.")
    count = _integer(data.get("count"), "Этажей в здании")
    reference_floor = _integer(data.get("referenceFloor"), "Опорный этаж")
    if reference_floor > count:
        raise ValueError("Опорный этаж должен находиться в здании.")
    reference_pressure = _pressure(data.get("referencePressure"), "Опорное давление")
    measured = _pressure(data.get("measuredPressure"), "Измеренное давление")
    estimated = reference_floor + SCALE_HEIGHT * math.log(reference_pressure / measured) / step
    nearest = max(1, min(count, math.floor(estimated + 0.5)))
    return {"floor": nearest, "estimatedFloor": estimated, "withinBuilding": 0.5 <= estimated <= count + 0.5}
