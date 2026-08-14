using Microsoft.AspNetCore.RateLimiting;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

builder.Services.AddRateLimiter(rateLimiterOptions =>
{
    rateLimiterOptions.AddFixedWindowLimiter("fixed", options =>
    {
        options.Window = TimeSpan.FromSeconds(10);
        options.PermitLimit = 5;
    });
});

// 게이트웨이 자체가 요청을 받을 수 있는지 확인한다.
// 업스트림 상태는 여기서 보지 않는다. 각 서비스가 자기 /health 로 판단하고,
// 업스트림 장애가 게이트웨이 파드의 재시작으로 번지면 안 된다.
builder.Services.AddHealthChecks();

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseRateLimiter();

// 프록시 라우팅보다 먼저 등록한다.
// MapReverseProxy 가 /health 를 업스트림으로 넘겨버리면 프로브가 엉뚱한 응답을 받는다.
app.MapHealthChecks("/health");

app.MapReverseProxy();

app.Run();
