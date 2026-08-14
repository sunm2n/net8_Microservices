using FluentAssertions;
using Ordering.Domain.Exceptions;
using Ordering.Domain.ValueObjects;
using Xunit;

namespace Ordering.Domain.Tests;

/// <summary>
/// 값 객체의 생성 규칙을 확인한다.
///
/// 이 타입들은 Of 팩터리에서만 만들어지고 생성자가 private 이다.
/// 규칙이 깨지면 잘못된 값이 도메인 안으로 들어와 한참 뒤에 드러난다.
/// </summary>
public class ValueObjectTests
{
    [Fact]
    public void OrderId_빈_Guid_는_거부한다()
    {
        var act = () => OrderId.Of(Guid.Empty);

        act.Should().Throw<DomainException>()
            .WithMessage("*OrderId cannot be empty*");
    }

    [Fact]
    public void OrderId_정상_Guid_는_그_값을_보존한다()
    {
        var value = Guid.NewGuid();

        OrderId.Of(value).Value.Should().Be(value);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void OrderName_비어있는_값은_거부한다(string? value)
    {
        var act = () => OrderName.Of(value!);

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Payment_CVV_는_3자리를_넘을_수_없다()
    {
        var act = () => Payment.Of("PoC Card", "4111111111111111", "12/30", "1234", 1);

        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Fact]
    public void Payment_정상_입력은_값을_보존한다()
    {
        var payment = Payment.Of("PoC Card", "4111111111111111", "12/30", "123", 1);

        payment.CardNumber.Should().Be("4111111111111111");
        payment.CVV.Should().Be("123");
        payment.PaymentMethod.Should().Be(1);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void Payment_카드번호가_비어있으면_거부한다(string? cardNumber)
    {
        var act = () => Payment.Of("PoC Card", cardNumber!, "12/30", "123", 1);

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void CustomerId_빈_Guid_는_거부한다()
    {
        var act = () => CustomerId.Of(Guid.Empty);

        act.Should().Throw<DomainException>();
    }

    [Fact]
    public void ProductId_빈_Guid_는_거부한다()
    {
        var act = () => ProductId.Of(Guid.Empty);

        act.Should().Throw<DomainException>();
    }
}
