"""Estimate altitude from a barometer and a nearby outdoor reference."""


def altitude_from_pressure(
    indoor_pressure_hpa: float,
    outdoor_pressure_hpa: float,
    outdoor_altitude_m: float = 0.0,
) -> float:
    """Return altitude in metres relative to sea level.

    Pressures must be measured in hPa at roughly the same time. The outdoor
    value must be *station pressure* measured at ``outdoor_altitude_m``, not
    weather-report pressure adjusted to sea level. For nearby locations this
    uses the standard-atmosphere barometric approximation. Weather and indoor
    ventilation can affect accuracy.

    Example: ``altitude_from_pressure(1001.0, 1013.25, 0.0)``.
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
