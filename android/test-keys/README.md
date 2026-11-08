# Chave de TESTE do Fast run

`fast-run-teste.jks` assina os APKs de teste (debug e release sem `key.properties`).
Fica no repositório de propósito: assim qualquer build gera APKs com a mesma
assinatura, o que mantém o login Google funcionando (SHA-1 registrado no Firebase)
e permite instalar uma versão nova por cima da anterior.

- Senha do arquivo e da chave: `fastrun-teste` · alias: `teste`
- SHA-1: `FA:52:10:B8:72:DB:D6:D4:25:E5:AB:FD:E4:D7:51:37:D0:8A:0C:53`
- SHA-256: `1D:7A:27:81:68:A3:FF:E3:2F:44:A1:66:FD:48:40:DF:FB:29:4A:1F:D1:41:D3:F3:EB:9F:2A:50:8A:9B:3B:13`

**Não use esta chave na Play Store.** A chave de publicação é gerada por você
(docs/PUBLICAR.md, passo 4), fica fora do git em `android/key.properties`, e o
SHA-1 dela também precisa ser cadastrado no Firebase.
