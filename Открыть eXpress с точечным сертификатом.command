#!/bin/zsh

# Точечное исключение только для текущего сертификата express.moex.com.
# Не используем глобальный --ignore-certificate-errors.
spki_hash="QpZAHH2/hqIFM3vGpN+WEWe8MxwXUDp/+VgalT7cefw="

open -na "/Applications/eXpress_Corporate.app" --args \
  "--ignore-certificate-errors-spki-list=${spki_hash}"
