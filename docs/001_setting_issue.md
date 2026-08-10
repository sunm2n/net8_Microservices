# macOS 환경 세팅 이슈 정리

Windows 기준으로 만들어진 강의 소스코드를 macOS(Apple Silicon)에서 `docker compose up`으로 실행하며 겪은 문제와 해결 과정을 정리한다.

## 1. `${APPDATA}` 볼륨 마운트 경로 문제

### 증상

```
Error response from daemon: mounts denied:
The path /Microsoft/UserSecrets is not shared from the host and is not known to Docker.
```

### 원인

`docker-compose.override.yml`의 각 API 서비스(`catalog.api`, `basket.api`, `discount.grpc`, `ordering.api`, `yarpapigateway`, `shopping.web`)에 Visual Studio가 "Docker Compose 지원 추가" 시 자동 생성해주는 다음 볼륨 마운트가 있었다.

```yaml
volumes:
  - ${APPDATA}/Microsoft/UserSecrets:/home/app/.microsoft/usersecrets:ro
  - ${APPDATA}/ASP.NET/Https:/home/app/.aspnet/https:ro
```

`APPDATA`는 Windows 전용 환경변수라 macOS에는 존재하지 않는다. 빈 문자열로 치환되면서 `/Microsoft/UserSecrets`, `/ASP.NET/Https`라는 루트 경로를 마운트하려다 실패했다.

### 해결

6개 서비스에서 위 `volumes` 블록을 제거했다. 컨테이너 간 통신에 필요한 값들은 이미 `environment`에 별도로 주입되고 있어 해당 볼륨이 없어도 동작에는 지장이 없다.
