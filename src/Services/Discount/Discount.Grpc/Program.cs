using Discount.Grpc.Data;
using Discount.Grpc.Services;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddGrpc();
builder.Services.AddDbContext<DiscountContext>(opts =>
        opts.UseSqlite(builder.Configuration.GetConnectionString("Database")));

// 이 서비스는 HTTP/2 전용이라 다른 서비스처럼 /health 를 열 수 없다.
// gRPC 표준 health checking 프로토콜(grpc.health.v1.Health)을 구현해
// Kubernetes 의 grpc 프로브가 직접 확인하게 한다.
//
// DbContext 검사를 함께 건다. 포트만 보는 프로브로는
// SQLite 마이그레이션이 실패해도 Ready 로 잡히고,
// Basket 이 할인을 받지 못하는데 예외 없이 정가가 적용된다.
builder.Services.AddGrpcHealthChecks()
    .AddDbContextCheck<DiscountContext>("discountdb");

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseMigration();
app.MapGrpcService<DiscountService>();
app.MapGrpcHealthChecksService();
app.MapGet("/", () => "Communication with gRPC endpoints must be made through a gRPC client. To learn how to create a client, visit: https://go.microsoft.com/fwlink/?linkid=2086909");

app.Run();
