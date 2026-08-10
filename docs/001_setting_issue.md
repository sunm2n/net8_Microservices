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

## 3. macOS에 dev-cert가 없어 HTTPS 바인딩 실패

### 증상

1번 이슈를 고치며 `${APPDATA}/ASP.NET/Https` 볼륨(dev-cert 마운트)도 함께 제거됐는데, 각 API 서비스의 환경변수에는 여전히 `ASPNETCORE_HTTPS_PORTS=8081`이 남아있어 컨테이너가 뜨자마자 죽었다(`Exited (133)`).

```
Unhandled exception. System.InvalidOperationException: Unable to configure HTTPS endpoint.
No server certificate was specified, and the default developer certificate
could not be found or is out of date.
```

### 원인

`${APPDATA}/ASP.NET/Https` 마운트는 Windows에서 `dotnet dev-certs https`로 생성한 인증서를 컨테이너에 넣어주기 위한 것이었다. macOS에서 동일하게 맞추려면 호스트에 인증서를 새로 만들고 서비스마다 인증서 경로/비밀번호 환경변수를 추가로 잡아줘야 해서 설정이 번거롭다. 반면 HTTPS/TLS 설정은 이 강의(DDD·CQRS·Vertical/Clean Architecture)가 다루는 애플리케이션/도메인 레이어 학습 내용과는 무관한 전송 계층 문제라, 로컬 Docker 환경에서는 컨테이너 간 통신을 HTTP로 통일하는 쪽이 실용적이라고 판단했다.

### 해결

- 6개 API 서비스에서 `ASPNETCORE_HTTPS_PORTS` 환경변수와 `8081` 포트 매핑을 제거했다. YARP 게이트웨이(`appsettings.json`)는 이미 클러스터 대상 주소를 `http://`로 설정하고 있어 별도 수정이 필요 없었다.
- `basket.api`가 `discount.grpc`를 호출할 때 쓰는 `GrpcSettings__DiscountUrl`을 `https://discount.grpc:8081` → `http://discount.grpc:8080`으로 변경했다.
- gRPC는 기본적으로 TLS 위에서 HTTP/2를 사용하므로, 평문 HTTP/2(h2c) 호출을 허용하기 위해 `Basket.API/Program.cs` 최상단에 다음 스위치를 추가했다(Microsoft 공식 문서에서 권장하는 방식).

```csharp
AppContext.SetSwitch("System.Net.Http.SocketsHttpHandler.Http2UnencryptedSupport", true);
```

  `discount.grpc`의 `appsettings.json`에는 이미 `Kestrel:EndpointDefaults:Protocols = Http2`가 설정되어 있어 서버 쪽은 별도 수정 없이 HTTP 포트(8080)에서 h2c를 지원한다.
