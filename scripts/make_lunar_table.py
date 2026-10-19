"""한국 음력 표(Core `KoreanLunarData.swift`)를 만든다.

사용법:
    pip install korean_lunar_calendar==0.4.0
    python3 scripts/make_lunar_table.py > Packages/DayGridCore/Sources/DayGridCore/KoreanLunarData.swift

korean_lunar_calendar(MIT)는 한국천문연구원(KASI) 기준 데이터를 쓴다. 중국 음력과는 해에 따라 하루씩 다르므로
(예: 2027년 설날은 한국 2월 7일, 중국 2월 6일) 운영체제의 `.chinese` 달력 대신 이 표를 쓴다.

해마다 (음력 1월 1일의 양력 yyyymmdd, 윤달(없으면 0), 달 크기 비트)를 담는다.
달 크기 비트는 그 해의 달을 순서대로(윤달은 그 달 바로 뒤) 놓았을 때 i번째 달이 30일이면 i번째 비트가 1이다.
"""
import sys

from korean_lunar_calendar import KoreanLunarCalendar

FIRST_YEAR = 1900
LAST_YEAR = 2049


def lunar_days(calendar, year, month, leap):
    return calendar._KoreanLunarCalendar__getLunarDays(year, month, leap)


def leap_month(calendar, year):
    data = calendar._KoreanLunarCalendar__getLunarData(year)
    return calendar._KoreanLunarCalendar__getLunarIntercalationMonth(data)


def main():
    calendar = KoreanLunarCalendar()
    rows = []
    for year in range(FIRST_YEAR, LAST_YEAR + 1):
        calendar.setLunarDate(year, 1, 1, False)
        new_year = int(calendar.SolarIsoFormat().replace("-", ""))
        leap = leap_month(calendar, year)
        months = []
        for month in range(1, 13):
            months.append(lunar_days(calendar, year, month, False))
            if month == leap:
                months.append(lunar_days(calendar, year, month, True))
        bits = sum(1 << index for index, days in enumerate(months) if days == 30)
        assert all(days in (29, 30) for days in months), (year, months)
        rows.append((year, new_year, leap, bits))

    out = sys.stdout
    out.write("// 이 파일은 scripts/make_lunar_table.py로 만든다. 직접 고치지 않는다.\n")
    out.write("// 자료: korean_lunar_calendar 0.4.0 (MIT, 한국천문연구원 기준)\n\n")
    out.write("enum KoreanLunarData {\n")
    out.write(f"    static let firstYear = {FIRST_YEAR}\n")
    out.write(f"    static let lastYear = {LAST_YEAR}\n\n")
    out.write("    /// (음력 1월 1일의 양력 yyyymmdd, 윤달(없으면 0), 30일인 달의 비트)\n")
    out.write("    static let years: [(newYear: Int, leapMonth: Int, bigMonths: Int)] = [\n")
    for year, new_year, leap, bits in rows:
        out.write(f"        ({new_year}, {leap}, 0x{bits:04x}), // {year}\n")
    out.write("    ]\n")
    out.write("}\n")


if __name__ == "__main__":
    main()
