using FluentAssertions;
using Ordering.Domain.Enums;
using Ordering.Domain.Events;
using Ordering.Domain.Models;
using Ordering.Domain.ValueObjects;
using Xunit;

namespace Ordering.Domain.Tests;

/// <summary>
/// Order 집계의 불변식과 도메인 이벤트를 확인한다.
///
/// 주문 금액과 항목 구성은 결제로 이어지는 값이라
/// 잘못된 상태가 저장된 뒤에는 되돌리기 어렵다.
/// </summary>
public class OrderTests
{
    private static Order NewOrder() => Order.Create(
        OrderId.Of(Guid.NewGuid()),
        CustomerId.Of(Guid.NewGuid()),
        OrderName.Of("ORD_TEST"),
        Address.Of("PoC", "Verify", "poc@example.com", "Seoul", "KR", "Seoul", "04524"),
        Address.Of("PoC", "Verify", "poc@example.com", "Seoul", "KR", "Seoul", "04524"),
        Payment.Of("PoC Card", "4111111111111111", "12/30", "123", 1));

    [Fact]
    public void 생성하면_Pending_상태로_시작한다()
    {
        NewOrder().Status.Should().Be(OrderStatus.Pending);
    }

    [Fact]
    public void 생성하면_OrderCreatedEvent_가_쌓인다()
    {
        var order = NewOrder();

        order.DomainEvents.Should().ContainSingle()
            .Which.Should().BeOfType<OrderCreatedEvent>();
    }

    [Fact]
    public void 항목이_없으면_총액은_0이다()
    {
        NewOrder().TotalPrice.Should().Be(0);
    }

    [Fact]
    public void 총액은_수량과_단가의_합이다()
    {
        var order = NewOrder();

        order.Add(ProductId.Of(Guid.NewGuid()), quantity: 2, price: 950);
        order.Add(ProductId.Of(Guid.NewGuid()), quantity: 3, price: 100);

        // 2 × 950 + 3 × 100
        order.TotalPrice.Should().Be(2200);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void 수량이_0이하면_항목을_담을_수_없다(int quantity)
    {
        var order = NewOrder();

        var act = () => order.Add(ProductId.Of(Guid.NewGuid()), quantity, price: 100);

        act.Should().Throw<ArgumentOutOfRangeException>();
        order.OrderItems.Should().BeEmpty();
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-100)]
    public void 단가가_0이하면_항목을_담을_수_없다(decimal price)
    {
        var order = NewOrder();

        var act = () => order.Add(ProductId.Of(Guid.NewGuid()), quantity: 1, price);

        act.Should().Throw<ArgumentOutOfRangeException>();
        order.OrderItems.Should().BeEmpty();
    }

    [Fact]
    public void 항목을_제거하면_총액에서_빠진다()
    {
        var order = NewOrder();
        var productId = ProductId.Of(Guid.NewGuid());

        order.Add(productId, quantity: 2, price: 500);
        order.TotalPrice.Should().Be(1000);

        order.Remove(productId);

        order.OrderItems.Should().BeEmpty();
        order.TotalPrice.Should().Be(0);
    }

    [Fact]
    public void 없는_항목을_제거해도_예외가_나지_않는다()
    {
        var order = NewOrder();

        var act = () => order.Remove(ProductId.Of(Guid.NewGuid()));

        act.Should().NotThrow();
    }

    [Fact]
    public void 갱신하면_OrderUpdatedEvent_가_쌓인다()
    {
        var order = NewOrder();
        order.ClearDomainEvents();

        order.Update(
            OrderName.Of("ORD_UPDATED"),
            Address.Of("PoC", "Verify", "poc@example.com", "Busan", "KR", "Busan", "48058"),
            Address.Of("PoC", "Verify", "poc@example.com", "Busan", "KR", "Busan", "48058"),
            Payment.Of("PoC Card", "4111111111111111", "12/31", "321", 2),
            OrderStatus.Completed);

        order.Status.Should().Be(OrderStatus.Completed);
        order.DomainEvents.Should().ContainSingle()
            .Which.Should().BeOfType<OrderUpdatedEvent>();
    }

    [Fact]
    public void ClearDomainEvents_는_비우고_비운_것을_돌려준다()
    {
        var order = NewOrder();

        var cleared = order.ClearDomainEvents();

        cleared.Should().ContainSingle();
        order.DomainEvents.Should().BeEmpty();
    }

    [Fact]
    public void OrderItems_는_외부에서_직접_수정할_수_없다()
    {
        // 읽기 전용으로 노출해야 집계 밖에서 불변식을 우회할 수 없다.
        NewOrder().OrderItems.Should().BeAssignableTo<IReadOnlyList<OrderItem>>();
    }
}
