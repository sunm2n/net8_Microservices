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

## 2. `postgres:latest` 버전 드리프트로 인한 재시작 루프

### 증상

`catalogdb`, `basketdb` 컨테이너가 `Restarting (1)` 상태를 반복했다.

```
Error: in 18+, these Docker images are configured to store database data in a
       format which is compatible with "pg_ctlcluster"...
       Counter to that, there appears to be PostgreSQL data in:
         /var/lib/postgresql/data (unused mount/volume)
```

### 원인

`docker-compose.yml`이 버전 태그 없이 `image: postgres`(= `latest`)를 사용하고 있었다. Docker Hub의 `postgres:latest`가 현재 Postgres 18을 가리키는데, Postgres 18부터 컨테이너 내부 데이터 디렉터리 구조가 바뀌면서 이전 실행에서 초기화된 볼륨(`postgres_catalog`, `postgres_basket`)의 데이터 포맷과 맞지 않아 기동 때마다 죽었다.

### 해결

`catalogdb`, `basketdb`의 이미지를 `postgres:17`로 고정했다. 이 프로젝트는 EF Core/Npgsql 표준 SQL만 사용하므로 메이저 버전에 따른 호환성 문제는 없고, 최신 `latest` 태그를 그대로 쓰면 Docker Hub 쪽 이미지가 갱신될 때마다 동일한 문제가 재발할 수 있어 버전을 명시적으로 고정하는 편이 안전하다.
