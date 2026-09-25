namespace SemiOtonom.Domain.Common;

/// <summary>Bir aggregate'in yayınladığı domain olayı.</summary>
public interface IDomainEvent
{
    DateTime OccurredOn { get; }
}
