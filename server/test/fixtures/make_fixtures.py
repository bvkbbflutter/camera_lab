#!/usr/bin/env python3
"""
Generates real test fixture images with genuine embedded EXIF/GPS metadata,
used by the Node test suite to verify the server's own EXIF parser against
a known-good source (Pillow + piexif) rather than hand-crafted byte arrays.
"""
import io
import os
import piexif
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def deg_to_dms_rational(deg_float):
    deg_float = abs(deg_float)
    d = int(deg_float)
    m_float = (deg_float - d) * 60
    m = int(m_float)
    s = round((m_float - m) * 60 * 100)
    return [(d, 1), (m, 1), (s, 100)]


def build_exif_bytes(lat=17.385044, lon=78.486671, alt=530.0,
                      date="2026:09:24 10:42:31", make="Samsung", model="SM-S928B",
                      orientation=1, xres=300, yres=300, width=1920, height=1440):
    zeroth = {
        piexif.ImageIFD.Make: make,
        piexif.ImageIFD.Model: model,
        piexif.ImageIFD.Orientation: orientation,
        piexif.ImageIFD.XResolution: (xres, 1),
        piexif.ImageIFD.YResolution: (yres, 1),
        piexif.ImageIFD.ResolutionUnit: 2,  # inches
        piexif.ImageIFD.Software: "CameraLab POC 1.0",
        piexif.ImageIFD.DateTime: date,
    }
    exif_ifd = {
        piexif.ExifIFD.DateTimeOriginal: date,
        piexif.ExifIFD.DateTimeDigitized: date,
        piexif.ExifIFD.OffsetTimeOriginal: "+05:30",
        piexif.ExifIFD.SubSecTimeOriginal: "123",
        piexif.ExifIFD.PixelXDimension: width,
        piexif.ExifIFD.PixelYDimension: height,
        piexif.ExifIFD.ExposureTime: (1, 120),
        piexif.ExifIFD.FNumber: (18, 10),
        piexif.ExifIFD.ISOSpeedRatings: 100,
        piexif.ExifIFD.FocalLength: (26, 1),
        piexif.ExifIFD.LensModel: "Back Camera 26mm f/1.8",
    }
    gps_ifd = {}
    if lat is not None and lon is not None:
        gps_ifd = {
            piexif.GPSIFD.GPSLatitudeRef: "N" if lat >= 0 else "S",
            piexif.GPSIFD.GPSLatitude: deg_to_dms_rational(lat),
            piexif.GPSIFD.GPSLongitudeRef: "E" if lon >= 0 else "W",
            piexif.GPSIFD.GPSLongitude: deg_to_dms_rational(lon),
            piexif.GPSIFD.GPSAltitudeRef: 0,
            piexif.GPSIFD.GPSAltitude: (int(alt * 100), 100),
            piexif.GPSIFD.GPSDateStamp: "2026:09:24",
        }
    exif_dict = {"0th": zeroth, "Exif": exif_ifd, "GPS": gps_ifd, "1st": {}, "thumbnail": None}
    return piexif.dump(exif_dict)


def make_source_image(width=1920, height=1440):
    img = Image.new("RGB", (width, height))
    px = img.load()
    for y in range(height):
        for x in range(width):
            px[x, y] = ((x * 255 // width), (y * 255 // height), 128)
    return img


def main():
    img = make_source_image()
    exif_bytes = build_exif_bytes()

    # JPEG with full EXIF + GPS
    jpeg_path = os.path.join(HERE, "with_gps.jpg")
    img.save(jpeg_path, format="JPEG", quality=85, exif=exif_bytes)

    # JPEG with EXIF but no GPS (location disabled)
    exif_no_gps = build_exif_bytes(lat=None, lon=None)
    jpeg_no_gps_path = os.path.join(HERE, "no_gps.jpg")
    img.save(jpeg_no_gps_path, format="JPEG", quality=85, exif=exif_no_gps)

    # Plain JPEG, no EXIF at all
    plain_path = os.path.join(HERE, "no_exif.jpg")
    img.save(plain_path, format="JPEG", quality=85)

    # PNG with eXIf chunk (Pillow supports this via exif= since 9.1)
    png_path = os.path.join(HERE, "with_gps.png")
    img.save(png_path, format="PNG", exif=exif_bytes)

    # WebP (lossless) with EXIF
    webp_path = os.path.join(HERE, "with_gps.webp")
    img.save(webp_path, format="WEBP", lossless=True, exif=exif_bytes)

    # WebP lossy with EXIF
    webp_lossy_path = os.path.join(HERE, "with_gps_lossy.webp")
    img.save(webp_lossy_path, format="WEBP", quality=80, exif=exif_bytes)

    # A tiny corrupt file for negative tests
    with open(os.path.join(HERE, "corrupt.jpg"), "wb") as f:
        f.write(b"\xff\xd8\xff\xe0not a real jpeg body")

    # A non-image file
    with open(os.path.join(HERE, "not_an_image.txt"), "wb") as f:
        f.write(b"hello world, this is not an image")

    for name in ["with_gps.jpg", "no_gps.jpg", "no_exif.jpg", "with_gps.png", "with_gps.webp", "with_gps_lossy.webp"]:
        p = os.path.join(HERE, name)
        print(f"{name}: {os.path.getsize(p)} bytes")


if __name__ == "__main__":
    main()
