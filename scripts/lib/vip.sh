#!/usr/bin/env bash
# vip.sh — локальная проверка VIP-токена для установщика.
# Без сетевых запросов: бот может лежать, а уже выданные токены продолжат работать.

VIP_SECRET_SALT="${VIP_SECRET_SALT:-srbtl_vip_2026_K7pQdR2mB4nX8vY3cFgT6wH1sJ5eLuZa}"

verify_vip_token() {
  local token="$1"
  [[ "$token" =~ ^VIP-[A-F0-9]{16}-[A-F0-9]{8}$ ]] || return 1

  local payload="${token:4:16}"
  local signature="${token:21:8}"
  local expected
  expected=$(
    printf 'SIGN%s%s' "$payload" "$VIP_SECRET_SALT" \
      | shasum -a 256 \
      | cut -c1-8 \
      | tr 'a-f' 'A-F'
  )

  [[ "$signature" == "$expected" ]]
}
