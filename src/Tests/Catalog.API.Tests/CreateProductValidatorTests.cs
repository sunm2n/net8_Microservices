using Catalog.API.Products.CreateProduct;
using FluentAssertions;
using FluentValidation.TestHelper;
using Xunit;

namespace Catalog.API.Tests;

/// <summary>
/// 상품 생성 명령의 검증 규칙을 확인한다.
///
/// 이 검증기는 ValidationBehavior 를 통해 MediatR 파이프라인에서 돌아간다.
/// 규칙이 빠지면 잘못된 상품이 그대로 저장되고, 가격이 0 이하인 항목은
/// 장바구니 총액 계산까지 오염시킨다.
/// </summary>
public class CreateProductValidatorTests
{
    private readonly CreateProductCommandValidator _validator = new();

    private static CreateProductCommand ValidCommand() => new(
        Name: "IPhone X",
        Category: new List<string> { "Smart Phone" },
        Description: "설명",
        ImageFile: "product-1.png",
        Price: 950);

    [Fact]
    public void 정상_명령은_통과한다()
    {
        _validator.TestValidate(ValidCommand()).ShouldNotHaveAnyValidationErrors();
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    public void 이름이_비어있으면_거부한다(string? name)
    {
        var command = ValidCommand() with { Name = name! };

        _validator.TestValidate(command)
            .ShouldHaveValidationErrorFor(x => x.Name);
    }

    [Fact]
    public void 분류가_비어있으면_거부한다()
    {
        var command = ValidCommand() with { Category = new List<string>() };

        _validator.TestValidate(command)
            .ShouldHaveValidationErrorFor(x => x.Category);
    }

    [Fact]
    public void 이미지_파일이_비어있으면_거부한다()
    {
        var command = ValidCommand() with { ImageFile = "" };

        _validator.TestValidate(command)
            .ShouldHaveValidationErrorFor(x => x.ImageFile);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(-950)]
    public void 가격이_0이하면_거부한다(decimal price)
    {
        var command = ValidCommand() with { Price = price };

        _validator.TestValidate(command)
            .ShouldHaveValidationErrorFor(x => x.Price);
    }

    [Fact]
    public void 설명은_비어있어도_통과한다()
    {
        // 검증 규칙에 없다. 의도한 것인지 확인해 두는 의미의 테스트다.
        var command = ValidCommand() with { Description = "" };

        _validator.TestValidate(command).ShouldNotHaveAnyValidationErrors();
    }
}
