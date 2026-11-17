-- Corte DÚ Amigo · 008 · Ajustes de segurança apontados pelo verificador do Supabase
-- Rodar depois da 007. Pode rodar mais de uma vez sem estragar nada.

-- Caminho de busca fixo também nas funções simples: assim nenhum objeto com o mesmo nome
-- em outro schema muda o resultado delas.
alter function fuso() set search_path = public;
alter function normalizar_telefone(text) set search_path = public;
alter function hoje_local() set search_path = public;
alter function situacao_assinatura(text, date) set search_path = public;

-- Funções auxiliares só rodam por dentro das outras (que são security definer e por isso
-- continuam podendo chamá-las). Ninguém precisa chamá-las direto pela API: fecha pra todos.
-- Ficam liberadas eh_dono(), eh_equipe() e barbeiro_atual(), porque as políticas de RLS
-- rodam com o papel de quem consulta e precisam executá-las.
revoke execute on function
  cfg(text),
  cfg_int(text, integer),
  pode_barbeiro(uuid),
  exigir_equipe(),
  exigir_dono(),
  duracao_servicos(uuid[]),
  bloqueio_conflita(uuid, timestamptz, timestamptz),
  slot_valido(uuid, timestamptz, timestamptz),
  resumo_agendamento(uuid),
  plano_do_cliente(uuid),
  bloqueios_do_dia(uuid, date),
  um_bloqueio_conflita(uuid, timestamptz, timestamptz, boolean, uuid, timestamptz, timestamptz),
  na_grade(uuid, timestamptz),
  validar_inicio(uuid, timestamptz)
from public, anon, authenticated;
