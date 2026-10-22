# Train timetable files shipped with the service

Official yearly passenger timetables published as open data on data.gov.ro under
the **Open Government Licence - Romania 1.0 (OGL-ROU-1.0)**, which allows reuse
and redistribution with attribution. They are the planned annual timetable, not
how trains are actually running: no delays, no real-time data.

| File | Operator | Dataset page | Valid | Exported | Original size | SHA-256 of the original `.xml` |
|---|---|---|---|---|---|---|
| `sntfc.xml.gz` | CFR Călători | https://data.gov.ro/dataset/mers-tren-sntfc-cfr-calatori-s-a | 14.12.2025 - 12.12.2026 | 03.12.2025 | 11,928,124 B | `97bebe5d4bec31bd37528db61bc75af2f13ad1259f31245165385cbc529fc467` |
| `interregional.xml.gz` | Interregional Călători | https://data.gov.ro/dataset/mers-tren-interregional-calatori | 14.12.2025 - 12.12.2026 | 03.12.2025 | 1,920,092 B | `70907f19816df9dd63625cd2e25f75666e51ef951a8ca4b325fc4bd86b1897cd` |

The files are the unmodified originals, only gzip-compressed (`gzip -9`).

Why they are bundled: from the hosted server the `robots.txt` of data.gov.ro
could not be read in time, so the downloader (which respects `robots.txt`)
rightly did not fetch the files. The files change once a year, so shipping them
is simpler and does not depend on that route.

## Yearly update (the timetable changes on the second Sunday of December)

1. Open the dataset pages above and download the new XML resources by hand.
2. `gzip -9 -c new.xml > sntfc.xml.gz` (and the same for the other file),
   replace the files here and update the table above.
3. Commit and push. Until then, after the validity end date the source reports
   `unavailable` ("Orarul a expirat") and returns no trains: it never serves an
   expired timetable.

To use a download instead of a bundled file, set `RAIL_SNTFC_URL` /
`RAIL_INTERREGIONAL_URL`; to keep the files elsewhere, set `RAIL_DATA_DIR`.
