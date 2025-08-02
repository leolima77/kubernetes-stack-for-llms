O que essa stack inclui:

MicroK8s como motor Kubernetes
Rancher, via Helm, para gestão visual do cluster
PostgreSQL com a extensão pgvector, instalado via Helm
Suporte completo a GPU com NVIDIA Container Toolkit + drivers + plugin
Ollama com o modelo gemma3:27b rodando localmente via API REST

Alguns detalhes:

1. Helm para tudo
Usei Helm para instalar o Rancher e o PostgreSQL, já com definições de senha, recursos de CPU/memória e exposição via NodePort. É direto e prático.
2. Rancher com cert-manager (sem ingress)
O Rancher roda sem ingress, só com NodePort. O cert-manager está lá apenas para cumprir sua função de “desbloquear” o Rancher — nada muito elaborado com TLS ou DNS automatizado.
3. PostgreSQL + pgvector pronto pra embeddings
Depois do deploy do banco, o script entra no pod e ativa a extensão pgvector. Pronto para guardar vetores de embeddings e rodar queries semânticas.
4. GPU NVIDIA operando com MicroK8s
Drivers, Container Toolkit, operador da NVIDIA e Device Plugin incluídos. Validação com pod nvidia/cuda usando nvidia-smi.
5. Ollama em produção com o mínimo viável
Instalação direta do Ollama, download do modelo gemma3:27b e um teste básico via cURL. É o suficiente para validar que o LLM está operacional com aceleração.

Para que serve isso?

- Essa stack pode ser útil para quem quer:
- Rodar LLMs com suporte a GPU
- Usar PostgreSQL vetorial em projetos com RAG
- Testar modelos e prototipar agentes inteligentes
- Kubernetes funcional e leve

