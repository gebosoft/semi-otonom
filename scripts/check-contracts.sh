CHANGED=$(git status --porcelain -- contracts/ packages/api-client-ts/src/ mobile/packages/api_client/)

if [[ -n "$CHANGED" ]]; then
  echo ""
  echo "HATA: Üretilmiş sözleşme dosyaları güncel değil."
  echo "Çalıştırın: ./scripts/generate-contracts.sh && git add -A"
  echo ""
  echo "$CHANGED"
  exit 1
fi

echo "✓ Sözleşmeler güncel"