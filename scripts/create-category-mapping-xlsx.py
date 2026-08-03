#!/usr/bin/env python3
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
from xml.sax.saxutils import escape
import csv

ROOT = Path(__file__).resolve().parents[1]
# Excel itself produces the distributable XLSX from CSV. Keep the hand-built package
# in /tmp so rerunning this data generator never overwrites that verified workbook.
OUTPUT = Path("/tmp/FitMatch_category_mapping_draft.xlsx")
CSV_OUTPUT = ROOT / "Docs" / "FitMatch_플랫폼_카테고리_매칭표.csv"
OBSERVED = ROOT / "Docs" / "Research" / "LiveProductSurvey-20260723" / "category-mappings.csv"

# FitMatch bundled taxonomy order. Platform values are source paths/keywords accepted by
# the current resolver or explicitly recorded in the live-product survey.
ROWS = [
    # category, detail, code, musinsa, uniqlo, status, note
    ("상의", "민소매", "tops/sleeveless", "상의 / 민소매 티셔츠; 스포츠/레저 / 상의 / 나시/민소매 티셔츠", "셔츠 > 민소매; 티셔츠 > 민소매", "조건부", "원본 명칭 우선, 없으면 소매 실측으로 보정"),
    ("상의", "반팔", "tops/short_sleeve", "상의 / 반소매 티셔츠; 스포츠/레저 / 상의 / 반소매 티셔츠", "셔츠 > 폴로셔츠; 티셔츠 > 반팔", "조건부", "반팔 키워드 또는 플랫폼별 소매 길이 기준"),
    ("상의", "7부", "tops/three_quarter_sleeve", "상의 / 7부 소매(상품명 기준)", "셔츠/티셔츠 > 7부(상품명 기준)", "조건부", "7부·3/4·three quarter 키워드 필요"),
    ("상의", "긴팔", "tops/long_sleeve", "상의 / 긴소매 티셔츠", "셔츠 > 긴팔; 티셔츠 > 긴팔", "조건부", "긴팔 키워드 또는 플랫폼별 소매 길이 기준"),
    ("상의", "기타 상의", "tops/other_tops", "상의 / 기타 상의", "셔츠/티셔츠 / 미분류", "검토 필요", "소매 실측이 있으면 민소매·반팔·긴팔로 재분류"),

    ("하의", "숏팬츠", "bottoms/short_pants", "바지 / 숏 팬츠", "팬츠 > 숏팬츠; 팬츠 > 쇼트팬츠", "확정", "반바지 키워드가 일반 팬츠보다 우선"),
    ("하의", "반바지", "bottoms/shorts", "바지 / 숏 팬츠; 스포츠/레저 / 하의 / 숏팬츠", "팬츠 > 반바지; 팬츠 > 쇼츠; 팬츠 > 버뮤다", "확정", "숏팬츠와 반바지는 표시 코드는 다르지만 비교 길이는 short"),
    ("하의", "크롭", "bottoms/cropped_pants", "바지 / 크롭(상품명 기준)", "팬츠 > 크롭; cropped", "조건부", "원본 경로/상품명 키워드"),
    ("하의", "7부", "bottoms/three_quarter_pants", "바지 / 7부(상품명 기준)", "팬츠 > 7부; 3/4 pants", "조건부", "7부를 9부·긴바지와 별도 비교"),
    ("하의", "9부", "bottoms/nine_tenths_pants", "바지 / 9부(상품명 기준)", "팬츠 > 9부; 앵클; ankle", "조건부", "9부를 긴바지와 별도 비교"),
    ("하의", "긴바지", "bottoms/long_pants", "바지 / 데님 팬츠; 코튼 팬츠; 슈트 팬츠/슬랙스; 트레이닝/조거 팬츠", "팬츠 > 진(청바지); 팬츠 > 치노팬츠; 팬츠 > 슬랙스; 팬츠 > 조거", "확정", "데님과 일반 팬츠는 같은 긴바지면 비교 가능"),
    ("하의", "기타 하의", "bottoms/other_bottoms", "바지 / 기타 하의; 스포츠/레저 / 하의 / 기타 바지", "팬츠 > 기타; 점프수트; 오버올", "검토 필요", "실측 길이가 있으면 세부 길이로 재분류"),

    ("레깅스", "숏", "leggings/short_leggings", "스포츠/레저 / 레깅스 / 숏", "레깅스 > 숏; AIRism 숏 레깅스", "조건부", "레깅스 의류군 안에서만 비교"),
    ("레깅스", "7부", "leggings/three_quarter_leggings", "스포츠/레저 / 레깅스 / 7부", "레깅스 > 7부", "조건부", "레깅스 의류군 안에서만 비교"),
    ("레깅스", "9부", "leggings/nine_tenths_leggings", "스포츠/레저 / 레깅스 / 9부", "레깅스 > 9부", "조건부", "레깅스 의류군 안에서만 비교"),
    ("레깅스", "롱", "leggings/long_leggings", "스포츠/레저 / 레깅스 / 롱", "레깅스 > 롱", "조건부", "일반 팬츠와 분리"),
    ("레깅스", "기타 레깅스", "leggings/other_leggings", "스포츠/레저 / 레깅스 / 기타", "레깅스 > 기타", "검토 필요", "상품명·실측 길이로 재분류"),
]

OUTER = [
    ("가디건", "cardigan", "아우터 / 카디건", "아우터 > 가디건"),
    ("바람막이", "windbreaker", "아우터 / 나일론/코치 재킷", "아우터 > 바람막이"),
    ("아노락", "anorak", "아우터 / 아노락", "아우터 > 아노락"),
    ("재킷", "jacket", "아우터 / 트레이닝 재킷; 나일론/코치 재킷", "아우터 > 재킷"),
    ("블레이저", "blazer", "아우터 / 슈트/블레이저 재킷", "아우터 > 블레이저"),
    ("점퍼", "jumper", "아우터 / 후드 집업; 점퍼", "아우터 > 점퍼"),
    ("블루종", "blouson", "아우터 / 블루종", "아우터 > 블루종"),
    ("플리스", "fleece", "아우터 / 플리스", "아우터 > 플리스"),
    ("경량패딩", "light_padding", "아우터 / 경량 패딩/패딩 베스트 / 경량 패딩", "아우터 > 경량패딩"),
    ("숏패딩", "short_padding", "아우터 / 숏 패딩", "아우터 > 숏패딩"),
    ("패딩", "padding", "아우터 / 패딩", "아우터 > 패딩"),
    ("롱패딩", "long_padding", "아우터 / 롱 패딩", "아우터 > 롱패딩"),
    ("코트", "coat", "아우터 / 코트", "아우터 > 코트"),
    ("트렌치코트", "trench_coat", "아우터 / 트렌치코트", "아우터 > 트렌치코트"),
    ("무스탕", "mouton", "아우터 / 무스탕", "아우터 > 무스탕"),
    ("조끼", "vest", "아우터 / 베스트", "아우터 > 베스트"),
    ("패딩조끼", "padded_vest", "아우터 / 경량 패딩/패딩 베스트", "아우터 > 패딩조끼"),
    ("기타 아우터", "other_outerwear", "아우터 / 기타 아우터", "아우터 / 미분류", "검토 필요"),
]
for detail, code, musinsa, uniqlo, *status in OUTER:
    ROWS.append(("아우터", detail, f"outerwear/{code}", musinsa, uniqlo,
                 status[0] if status else "조건부", "원본 세부 명칭 우선; 소매 분류는 실측으로 보정"))

ROWS += [
    ("스커트", "스커트", "skirts/skirt", "원피스/스커트 / 미니·미디·롱스커트", "원피스/스커트 > 스커트", "확정", "팬츠와 분리"),
    ("스커트", "기타 스커트", "skirts/other_skirts", "원피스/스커트 / 기타 스커트", "원피스/스커트 > 기타 스커트", "검토 필요", "스커트 실측 정의 확인"),
    ("원피스", "원피스", "dresses/one_piece", "원피스/스커트 / 미니·미디·맥시원피스", "원피스/스커트 > 원피스", "확정", "원피스 의류군 안에서 비교"),
    ("원피스", "기타 원피스", "dresses/other_dresses", "원피스/스커트 / 기타 원피스", "원피스/스커트 / 미분류", "검토 필요", "실측 항목 확인"),
]

UNDERWEAR = [
    ("속옷", "underwear", "속옷/홈웨어 / 속옷", "이너웨어 / 속옷"),
    ("남성 브리프", "men_briefs", "남성 속옷 / 브리프", "MEN / 이너웨어 / 브리프"),
    ("남성 트렁크", "men_trunks", "남성 속옷 / 트렁크", "MEN / 이너웨어 / 트렁크"),
    ("남성 런닝", "men_undershirt", "남성 속옷 / 런닝", "MEN / 이너웨어 / 런닝"),
    ("브라", "women_bra", "여성 속옷 / 브라", "WOMEN / 이너웨어 / 브라"),
    ("팬티", "women_panty", "여성 속옷 / 팬티", "WOMEN / 이너웨어 / 팬티"),
    ("캐미솔", "women_camisole", "여성 속옷 / 캐미솔", "WOMEN / 이너웨어 / 캐미솔"),
    ("슬립", "women_slip", "여성 속옷 / 슬립", "WOMEN / 이너웨어 / 슬립"),
]
for detail, code, musinsa, uniqlo in UNDERWEAR:
    ROWS.append(("속옷", detail, f"underwear/{code}", musinsa, uniqlo, "조건부", "성별·실측 항목 호환성 필요"))

SHOES = [("스니커즈", "sneakers"), ("러닝화", "running_shoes"), ("로퍼", "loafers"),
         ("부츠", "boots"), ("샌들", "sandals"), ("힐", "heels")]
for detail, code in SHOES:
    ROWS.append(("신발", detail, f"shoes/{code}", f"신발 / {detail}", f"신발 / {detail}",
                 "조건부", "발길이 1개 공통 실측으로 비교; 유니클로는 해당 상품이 없을 수 있음"))

ACCESSORIES = [("시계", "watch"), ("반지", "ring"), ("팔찌", "bracelet"), ("목걸이", "necklace"),
               ("가방", "bag"), ("모자", "hat"), ("벨트", "belt"), ("스카프", "scarf"), ("양말", "socks")]
for detail, code in ACCESSORIES:
    ROWS.append(("액세서리", detail, f"accessories/{code}", f"액세서리 / {detail}",
                 f"액세서리 / {detail}", "검토 필요", "현재 의류 실측 자동 비교 대상이 아님"))

ROWS += [
    ("홈웨어", "라운지웨어", "homewear/loungewear", "속옷/홈웨어 / 홈웨어", "라운지웨어", "검토 필요", "현재 ClothingCategory에서 독립 홈웨어를 기타로 받을 수 있음"),
    ("홈웨어", "기타 홈웨어", "homewear/other_homewear", "속옷/홈웨어 / 기타", "홈웨어 / 미분류", "검토 필요", "독립 카테고리 보강 필요"),
    ("기타", "스포츠웨어", "other/sportswear", "스포츠/레저", "SPORT UTILITY WEAR", "검토 필요", "실제 의류 형태로 재분류 필요"),
    ("기타", "수영복", "other/swimwear", "스포츠/레저 / 수영복", "수영복", "검토 필요", "전용 비교 정책 없음"),
    ("기타", "유니폼", "other/uniform", "유니폼", "확인된 매칭 없음", "미매칭", "전용 비교 정책 없음"),
    ("기타", "코스튬", "other/costume", "코스튬", "확인된 매칭 없음", "미매칭", "전용 비교 정책 없음"),
    ("기타", "기타", "other/other", "기타", "기타", "검토 필요", "자동 비교하지 않고 사용자 확인"),
]


def col_name(n):
    result = ""
    while n:
        n, r = divmod(n - 1, 26)
        result = chr(65 + r) + result
    return result


def sheet_xml(rows, widths, autofilter=True):
    out = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
           '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
           '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>',
           '<cols>']
    for i, width in enumerate(widths, 1):
        out.append(f'<col min="{i}" max="{i}" width="{width}" customWidth="1"/>')
    out.append('</cols><sheetData>')
    for r_idx, row in enumerate(rows, 1):
        style = 1 if r_idx == 1 else (3 if r_idx % 2 == 0 else 2)
        out.append(f'<row r="{r_idx}">')
        for c_idx, value in enumerate(row, 1):
            ref = f'{col_name(c_idx)}{r_idx}'
            text = escape(str(value or ""))
            out.append(f'<c r="{ref}" t="inlineStr" s="{style}"><is><t xml:space="preserve">{text}</t></is></c>')
        out.append('</row>')
    out.append('</sheetData>')
    if autofilter and rows:
        out.append(f'<autoFilter ref="A1:{col_name(len(rows[0]))}{len(rows)}"/>')
    out.append('</worksheet>')
    return ''.join(out)


def main():
    headers = ["성별/연령", "FitMatch 대분류", "FitMatch 상세분류", "FitMatch 코드",
               "비교 의류군", "길이 구분", "길이 판정 기준",
               "무신사 원본 카테고리", "유니클로 원본 카테고리", "매칭 상태", "비고"]

    def comparison_family(category, detail):
        if category == "상의":
            return "티셔츠/상의"
        if category == "하의":
            return "스커트" if "스커트" in detail else "팬츠"
        if category == "레깅스": return "레깅스"
        if category == "아우터": return "아우터"
        return category

    def length_info(category, detail):
        if category == "상의":
            mapping = {"민소매": "민소매", "반팔": "반팔", "7부": "7부", "긴팔": "긴팔"}
            value = mapping.get(detail, "미분류")
            rule = ("원본 키워드 우선. 미분류 시 유니클로 화장: 남 67/여 60/키즈·베이비 34.5cm; "
                    "무신사 소매: 남 52/여 43cm; 일반 세트인: 남 50/여 42cm 이하 짧음, 초과 김")
            return value, rule
        if category == "하의" and "스커트" not in detail:
            mapping = {"숏팬츠": "짧음", "반바지": "짧음", "크롭": "크롭",
                       "7부": "7부", "9부": "9부", "긴바지": "김"}
            value = mapping.get(detail, "미분류")
            rule = ("원본 키워드 우선. 미분류 시 유니클로 인심 46.5cm 이하 짧음; "
                    "무신사 총장 남 84/여 65/공용 74cm 이하 짧음, 초과 김. "
                    "7부·크롭·9부는 원본 키워드가 있을 때만 세분")
            return value, rule
        if category == "레깅스":
            mapping = {"숏": "짧음", "7부": "7부", "9부": "9부", "롱": "김"}
            return mapping.get(detail, "미분류"), "레깅스 세부 키워드·실측 길이"
        if category == "아우터":
            if detail in ("조끼", "패딩조끼"):
                return "민소매", "베스트/조끼 원본 분류"
            return "소매 실측 판정", "원본 소매 키워드 우선; 없으면 소매 실측"
        return "해당 없음", "이 의류군은 반팔/긴팔·반바지/긴바지 호환 필터를 사용하지 않음"

    expanded_rows = []
    for category, detail, code, musinsa, uniqlo, status, note in ROWS:
        length, length_rule = length_info(category, detail)
        expanded_rows.append(("통합(남성·여성·키즈·베이비)", category, detail, code,
                              comparison_family(category, detail), length, length_rule,
                              musinsa, uniqlo, status, note))
    main_rows = [headers] + expanded_rows
    with CSV_OUTPUT.open("w", encoding="utf-8-sig", newline="") as f:
        csv.writer(f).writerows(main_rows)

    observed_rows = [["쇼핑몰", "원본 카테고리 경로", "FitMatch 대분류 후보",
                      "FitMatch 상세분류 후보", "확정 여부", "예외와 충돌 사례"]]
    if OBSERVED.exists():
        with OBSERVED.open(encoding="utf-8-sig", newline="") as f:
            seen = set()
            for row in csv.reader(f):
                key = tuple(row)
                if key in seen or row == observed_rows[0]:
                    continue
                seen.add(key)
                observed_rows.append(row)

    notes = [
        ["항목", "내용"],
        ["작성 기준", "FitMatch 번들 택소노미, ParsedClosetClassification, 실상품 조사 자료(2026-07-23), 플랫폼별 사이즈 문서"],
        ["열 구성", "1열 FitMatch 대분류, 2열 FitMatch 상세분류, 3열 코드, 4열 무신사, 5열 유니클로"],
        ["확정", "원본 경로 키워드만으로 현재 로직의 분류가 결정됨"],
        ["조건부", "상품명, 원본 depth, 소매/바지 길이 실측 또는 성별을 함께 확인해야 함"],
        ["검토 필요", "플랫폼 상위 카테고리만으로는 세부 분류를 확정할 수 없음"],
        ["미매칭", "현재 수집 자료와 앱 로직에서 확인된 플랫폼 매칭이 없음"],
        ["중요", "플랫폼이 제공하는 카테고리가 변경될 수 있으므로 실제 파서 로그와 원본 depth를 함께 보존해야 함"],
    ]

    styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2"><font><sz val="11"/><name val="Apple SD Gothic Neo"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Apple SD Gothic Neo"/></font></fonts>
<fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1F4E78"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFEAF2F8"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border/><border><left style="thin"><color rgb="FFD9E1E8"/></left><right style="thin"><color rgb="FFD9E1E8"/></right><top style="thin"><color rgb="FFD9E1E8"/></top><bottom style="thin"><color rgb="FFD9E1E8"/></bottom></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'''

    workbook = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="카테고리 매칭표" sheetId="1" r:id="rId1"/><sheet name="실상품 관찰 원본" sheetId="2" r:id="rId2"/><sheet name="작성 기준" sheetId="3" r:id="rId3"/></sheets></workbook>'''
    rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/><Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'''
    root_rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'''
    content_types = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'''

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(OUTPUT, "w", ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", root_rels)
        z.writestr("xl/workbook.xml", workbook)
        z.writestr("xl/_rels/workbook.xml.rels", rels)
        z.writestr("xl/styles.xml", styles)
        z.writestr("xl/worksheets/sheet1.xml", sheet_xml(main_rows, [28, 15, 20, 25, 18, 16, 58, 55, 55, 14, 58]))
        z.writestr("xl/worksheets/sheet2.xml", sheet_xml(observed_rows, [14, 55, 20, 28, 16, 70]))
        z.writestr("xl/worksheets/sheet3.xml", sheet_xml(notes, [18, 100], autofilter=False))
    print(f"{CSV_OUTPUT}\t{len(ROWS)} mapping rows")
    print(f"{OUTPUT}\tinternal draft only\t{len(observed_rows)-1} observed rows")


if __name__ == "__main__":
    main()
