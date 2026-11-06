"""Flowseal winws to nfqws2-keenetic converter (MIT upstream core).

This stage intentionally omits the upstream deployment module: the feature is
conversion-only and must not be able to alter a router configuration.
"""

from .converter import ConversionError, ConversionResult, ConverterSettings, convert

__all__ = [
    "ConversionError",
    "ConversionResult",
    "ConverterSettings",
    "convert",
]
__version__ = "0.4.0"
