# Get Sessions - Sessões do Veeam

Script em **PowerShell 7** que consulta o histórico de execuções na API REST do Veeam Backup & Replication e gera relatórios em **JSON** e **CSV** com as sessões de backup, cópia de backup (backup copy) e restauração de um período.

> [!IMPORTANT]
> Este script **só consulta**. Ele não executa backups nem restaurações.

## Índice

1. [Início rápido (uso diário)](#início-rápido-uso-diário)
2. [Configuração inicial (só na primeira vez)](#configuração-inicial-só-na-primeira-vez)
3. [O arquivo config.psd1](#o-arquivo-configpsd1)
4. [Entendendo os resultados](#entendendo-os-resultados)
5. [Problemas comuns](#problemas-comuns)
6. [Avisos importantes](#avisos-importantes)

---

## Início rápido (uso diário)

Se a configuração inicial já foi feita neste computador, é só isto:

1. Abra o **PowerShell 7** (`pwsh`) e entre na pasta do projeto:
   ```powershell
   cd get-sessions
   ```
2. Abra o arquivo `config.psd1` e ajuste o período:
   ```powershell
   ReportStartDate = '2026-08-01'   # início (aaaa-mm-dd)
   ReportEndDate   = '2026-09-01'   # fim    (aaaa-mm-dd)
   ```
3. Execute:
   ```powershell
   pwsh -NoProfile -File ./functions/main.ps1
   ```
4. Pegue os relatórios (JSON e CSV) na pasta definida em `ReportOutputDirectory` (por padrão, `reports`, dentro da pasta do projeto). Se algo der errado, veja os logs na pasta `logs`.

Para usar outro arquivo de configuração:

```powershell
pwsh -NoProfile -File ./functions/main.ps1 -ConfigPath ./outro-config.psd1
```

---

## Configuração inicial (só na primeira vez)

### Pré-requisitos

- PowerShell 7.0 ou superior (`pwsh`)
- Acesso de rede à API REST do Veeam Backup & Replication
- Um usuário do Veeam com permissão para autenticar na API e consultar o histórico de sessões
- Módulos PowerShell `Microsoft.PowerShell.SecretManagement` e `Microsoft.PowerShell.SecretStore`
- Git (apenas se for clonar o repositório)

### 1. Baixar o projeto e instalar os módulos

```powershell
git clone https://github.com/angeluciel/get-sessions.git
cd get-sessions

Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser
Install-Module Microsoft.PowerShell.SecretStore -Scope CurrentUser
```

Se os módulos já estiverem instalados, pule a parte do `Install-Module`.

### 2. Criar o cofre de credenciais

Para que o usuário e a senha da API do Veeam **não fiquem escritos em nenhum arquivo do projeto**, o script lê essas informações de um cofre do Windows chamado **SecretStore**. Esta etapa é feita **uma única vez**.

> [!IMPORTANT]
> Execute os comandos abaixo com a **mesma conta do Windows** que vai executar o script.

> [!NOTE]
> Se o SecretStore já estiver configurado neste computador, **não** recrie. Reutilize o cofre e a senha existentes. Se o `LocalStore` já estiver registrado, não rode o `Register-SecretVault` de novo.

```powershell
# Pasta privada, fora do repositório
$secretsDir = Join-Path $HOME '.get-sessions'
New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
$credentialPath = Join-Path $secretsDir 'secretstore-password.xml'

# Escolha uma senha forte para o cofre
$storePassword = Read-Host 'Senha do SecretStore' -AsSecureString
$storePassword | Export-Clixml -Path $credentialPath

# Registre o cofre como padrão
Register-SecretVault -Name LocalStore `
    -ModuleName Microsoft.PowerShell.SecretStore `
    -DefaultVault

# Exige senha, mas não abre perguntas durante a automação
Set-SecretStoreConfiguration `
    -Authentication Password `
    -Interaction None `
    -Password $storePassword `
    -Confirm:$false

Unlock-SecretStore -Password $storePassword
```

O arquivo `secretstore-password.xml` guarda a senha que **destranca o cofre** (não é o token da API). Anote o caminho completo dele, você vai usar no `config.psd1` (campo `PathToCredential`). **Nunca coloque esse arquivo no repositório.**

### 3. Guardar o usuário e a senha da API do Veeam

Os nomes dos segredos são fixos. Não altere:

| Nome do segredo    | Conteúdo                      |
| ------------------ | ----------------------------- |
| `VeeamApiUser`     | Usuário da API do Veeam       |
| `VeeamApiPassword` | Senha desse usuário           |

```powershell
Set-Secret -Name VeeamApiUser `
    -Secret (Read-Host 'Usuário da API Veeam')

Set-Secret -Name VeeamApiPassword `
    -Secret (Read-Host 'Senha da API Veeam' -AsSecureString)

# Confirma que os segredos existem (sem mostrar os valores)
Get-SecretInfo
```

### 4. Criar o seu config.psd1

Na pasta do projeto:

```powershell
Copy-Item ./config.example.psd1 ./config.psd1
```

Depois ajuste os valores conforme a próxima seção.

---

## O arquivo config.psd1

Exemplo preenchido:

```powershell
@{
    VeeamBaseUrl          = 'http://localhost:9419'
    ReportStartDate       = '2026-08-01'
    ReportEndDate         = '2026-09-01'
    ReportOutputDirectory = 'reports'

    ApiVersion            = '1.3-rev2'
    PathToCredential      = 'C:\Users\seu.usuario\.get-sessions\secretstore-password.xml'

    LogDirectory          = 'logs'
    LogRetentionDays      = 7
    LogLevel              = 'INFO'
}
```

| Campo                   | O que é                                                                                              | Exemplo / observação                                      |
| ----------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `VeeamBaseUrl`          | Endereço da API REST do Veeam Backup & Replication.                                                  | `http://localhost:9419` (se o script roda no próprio servidor Veeam). Em outra máquina, use o endereço do servidor. |
| `ReportStartDate`       | Data de início do período, no formato `aaaa-mm-dd`.                                                  | `2026-08-01`                                              |
| `ReportEndDate`         | Data de fim do período, no formato `aaaa-mm-dd`.                                                     | `2026-09-01`                                              |
| `ReportOutputDirectory` | Pasta onde os relatórios são salvos. Caminho relativo à raiz do projeto.                             | `reports`                                                 |
| `ApiVersion`            | Versão da API REST do Veeam usada nas requisições.                                                   | Mantenha `1.3-rev2`, a menos que seu Veeam exija outra.   |
| `PathToCredential`      | Caminho do arquivo XML com a senha do SecretStore (criado no passo 2 da configuração inicial).       | Use o caminho da pasta privada `.get-sessions`.           |
| `LogDirectory`          | Pasta dos logs de execução e de erros.                                                               | `logs`                                                    |
| `LogRetentionDays`      | Por quantos dias os logs são mantidos.                                                               | `7`                                                       |
| `LogLevel`              | Nível de detalhe dos logs.                                                                           | `INFO`                                                    |

> [!WARNING]
> O arquivo `config.example.psd1` traz `C:\credential.xml` apenas como exemplo. Troque pelo caminho real do seu XML, de preferência em uma pasta privada da sua conta, e não na raiz do `C:\`.

---

## Entendendo os resultados

A cada execução, o script gera um relatório **JSON** e uma planilha **CSV** (separador `;`) na pasta definida em `ReportOutputDirectory`.

O relatório tem duas visões das mesmas sessões:

| Seção            | O que contém                                                                                                                                                     | Quando usar                                          |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `all-executions` | Todas as execuções exatamente como a API devolveu, sem tratamento.                                                                                               | Conferência técnica, investigação, auditoria.        |
| `beautified`     | Visão pronta para enviar ao cliente. Quando uma execução teve tentativas repetidas (retries), elas são agrupadas em uma só, usando o campo `originalSessionId`. Execuções sem vínculo conhecido ficam separadas. | Relatórios e resumos para o cliente.                 |

Dica: o CSV usa `;` como separador. Se abrir no Excel e as colunas vierem todas juntas, use **Dados → De Texto/CSV** e escolha `;` como delimitador.

---

## Problemas comuns

| Sintoma                                             | O que verificar                                                                                                                 |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| O comando não é reconhecido (`pwsh`)                | O PowerShell 7 não está instalado. O Windows PowerShell antigo (o azul) **não serve**.                                          |
| Erro de arquivo de configuração não encontrado      | Você esqueceu de criar o `config.psd1` (passo 4) ou está executando fora da pasta do projeto.                                   |
| Erro de módulo `SecretManagement`/`SecretStore`     | Rode os dois `Install-Module` da configuração inicial.                                                                          |
| Falha ao destravar o cofre ou ler os segredos       | Confira o caminho em `PathToCredential` e se você está usando a **mesma conta do Windows** que criou o cofre.                   |
| Falha de autenticação na API                        | O usuário ou a senha guardados em `VeeamApiUser` / `VeeamApiPassword` estão errados, ou o usuário não tem permissão na API.     |
| Não conecta na API                                  | Confira `VeeamBaseUrl` (endereço e porta), se o serviço REST do Veeam está ativo e se há liberação de rede/firewall.            |
| Relatório vazio ou sem as sessões esperadas         | Revise as datas em `config.psd1`. O filtro usa a data de **criação** da sessão (veja os avisos abaixo).                         |

Em qualquer erro, a pasta definida em `LogDirectory` tem o registro detalhado da execução.

---

## Avisos importantes

- O filtro de datas considera o horário de **criação da sessão**, e não quando ela terminou. Uma sessão criada antes do início do período e terminada dentro dele **não** entra.
- As datas são interpretadas no **fuso horário do computador** que executa o script.
- Nunca coloque no repositório o `config.psd1` com dados do seu ambiente nem o XML de senha do SecretStore.