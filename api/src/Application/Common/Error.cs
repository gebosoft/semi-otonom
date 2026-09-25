namespace SemiOtonom.Application.Common;

/// <summary>
/// Beklenen bir iş kuralı hatası: makine tarafından okunabilir <paramref name="Code"/> ve
/// insana dönük <paramref name="Message"/>. <see cref="Result{T}"/> içine implicit
/// dönüştüğü için handler'lar <c>return new Error("KOD", "mesaj");</c> yazabiliyor.
/// </summary>
public sealed record Error(string Code, string Message);
