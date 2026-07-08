# FitMatch Universal Links 설정

FitMatch Share Extension은 공유 URL을 App Group에 저장한 뒤 아래 Universal Link를 열도록 구성되어 있다.

```text
https://fitmatch.app/compare/shared
```

## 앱 설정

메인 앱 target의 `FitMatch.entitlements`에 Associated Domains를 등록해야 한다.

```text
applinks:fitmatch.app
```

Share Extension target에는 URL Scheme이나 Associated Domains를 등록하지 않는다.

> 주의: Apple Developer 계정의 App ID에서 Associated Domains capability가 켜져 있지 않거나 provisioning profile이 갱신되지 않은 상태에서 entitlement만 추가하면 Xcode 실기기 빌드가 실패한다. 현재 프로젝트 파일에는 빌드 실패를 막기 위해 이 entitlement를 기본 적용하지 않는다. 도메인/AASA/provisioning 준비가 끝난 뒤 Xcode Signing & Capabilities에서 메인 앱 target에 Associated Domains를 추가한다.

## 서버 설정

`fitmatch.app` 도메인의 아래 경로 중 하나에 `apple-app-site-association` 파일을 배포해야 한다.

```text
https://fitmatch.app/.well-known/apple-app-site-association
https://fitmatch.app/apple-app-site-association
```

파일은 확장자 없이 `application/json`으로 응답해야 한다.

## AASA 템플릿

`TEAM_ID`는 Apple Developer Team ID로 교체해야 한다.

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": [
          "TEAM_ID.io.github.ljy4337.FitMatch"
        ],
        "components": [
          {
            "/": "/compare/*"
          }
        ]
      }
    ]
  }
}
```

## 앱 처리 흐름

1. Share Extension이 공유된 상품 URL을 App Group `pendingProductURL`에 저장한다.
2. Share Extension이 `https://fitmatch.app/compare/shared`를 연다.
3. iOS가 Universal Link를 FitMatch 메인 앱으로 전달한다.
4. `ContentView.onOpenURL`이 링크를 받고 비교 탭으로 이동한다.
5. `SharedURLStore.consumePendingProductURL()`로 저장된 상품 URL을 읽어 자동 분석을 시작한다.

## 주의

Universal Link는 실제 기기, 실제 도메인, 올바른 provisioning profile에서만 검증 가능하다.
Simulator나 AASA가 배포되지 않은 상태에서는 Safari가 열릴 수 있다.
