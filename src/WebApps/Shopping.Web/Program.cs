var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddRazorPages();

builder.Services.AddRefitClient<ICatalogService>()
    .ConfigureHttpClient(c =>
    {
        c.BaseAddress = new Uri(builder.Configuration["ApiSettings:GatewayAddress"]!);
    });
builder.Services.AddRefitClient<IBasketService>()
    .ConfigureHttpClient(c =>
    {
        c.BaseAddress = new Uri(builder.Configuration["ApiSettings:GatewayAddress"]!);
    });
builder.Services.AddRefitClient<IOrderingService>()
    .ConfigureHttpClient(c =>
    {
        c.BaseAddress = new Uri(builder.Configuration["ApiSettings:GatewayAddress"]!);
    });

// 화면 자체가 응답할 수 있는지 확인한다.
// 게이트웨이 도달 여부는 보지 않는다. 게이트웨이가 잠시 흔들릴 때
// 이 파드까지 재시작되면 복구가 더 느려진다.
builder.Services.AddHealthChecks();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.UseAuthorization();

// UseHttpsRedirection 뒤에 두면 프로브가 307 로 밀린다.
// 컨테이너에는 HTTPS 포트가 없어 리다이렉트가 실제로 걸리지는 않지만,
// 나중에 TLS 를 켤 때 조용히 깨지지 않도록 인증 다음·라우팅 안에 둔다.
app.MapHealthChecks("/health");

app.MapRazorPages();

app.Run();
