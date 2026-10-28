"""Оценка высоты по барометру и ближайшему наружному опорному замеру."""


def altitude_from_pressure(
    indoor_pressure_hpa: float,
    outdoor_pressure_hpa: float,
    outdoor_altitude_m: float = 0.0,
) -> float:
    """Вернуть высоту над уровнем моря в метрах.

    Давление в помещении и снаружи измеряйте в гПа примерно в одно время.
    Наружный замер должен быть фактическим давлением на высоте
    ``outdoor_altitude_m``, а не приведённым к уровню моря давлением из прогноза.
    Используется приближение стандартной атмосферы для близких точек.
    Погода и вентиляция помещения могут влиять на точность.

    Пример: ``altitude_from_pressure(1001.0, 1013.25, 0.0)``.
    """
    for name, pressure in (
        ("indoor_pressure_hpa", indoor_pressure_hpa),
        ("outdoor_pressure_hpa", outdoor_pressure_hpa),
    ):
        if not 0 < pressure < float("inf"):
            raise ValueError(f"{name} must be a finite positive number")
    if not -float("inf") < outdoor_altitude_m < float("inf"):
        raise ValueError("outdoor_altitude_m must be finite")

    height_difference_m = 44330.0 * (
        1.0 - (indoor_pressure_hpa / outdoor_pressure_hpa) ** 0.190294957
    )
    return outdoor_altitude_m + height_difference_m
