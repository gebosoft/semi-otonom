namespace SemiOtonom.Application.Common;

/// <summary>
/// Application katmanının standart dönüş sarmalayıcısı. Beklenen iş kuralı hataları için
/// exception atmak yerine bu kullanılır — exception akış kontrolü aracı değil.
/// Implicit dönüşümler sayesinde handler dönüşleri okunur kalıyor:
/// <c>return order;</c> (başarı) / <c>return new Error("KOD", "mesaj");</c> (hata).
/// </summary>
public class Result<T>
{
    public bool IsSuccess { get; }

    public T? Value { get; }

    public Error? Error { get; }

    private Result(bool isSuccess, T? value, Error? error)
    {
        IsSuccess = isSuccess;
        Value = value;
        Error = error;
    }

    public static Result<T> Success(T value) => new(true, value, null);

    public static Result<T> Failure(Error error) => new(false, default, error);

    public static implicit operator Result<T>(T value) => Success(value);

    public static implicit operator Result<T>(Error error) => Failure(error);
}
