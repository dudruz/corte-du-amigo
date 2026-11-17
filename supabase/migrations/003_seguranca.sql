-- Corte DÚ Amigo · 003 · Segurança (RLS e permissões)
-- Regra geral: o público (anon) não lê nem grava nenhuma tabela.
-- Ele só executa as funções do agendamento. A equipe lê pelo RLS e grava pelas funções.

alter table barbeiros enable row level security;
alter table perfis enable row level security;
alter table servicos enable row level security;
alter table horarios_trabalho enable row level security;
alter table bloqueios enable row level security;
alter table clientes enable row level security;
alter table agendamentos enable row level security;
alter table agendamento_servicos enable row level security;
alter table formas_pagamento enable row level security;
alter table atendimentos enable row level security;
alter table pagamentos enable row level security;
alter table planos enable row level security;
alter table assinaturas enable row level security;
alter table usos_plano enable row level security;
alter table caixa_movimentos enable row level security;
alter table caixa_dia enable row level security;
alter table configuracoes enable row level security;

-- Cadastros: equipe lê, dono edita
create policy equipe_le on barbeiros for select to authenticated using (eh_equipe());
create policy dono_edita on barbeiros for all to authenticated using (eh_dono()) with check (eh_dono());
create policy equipe_le on servicos for select to authenticated using (eh_equipe());
create policy dono_edita on servicos for all to authenticated using (eh_dono()) with check (eh_dono());
create policy equipe_le on horarios_trabalho for select to authenticated using (eh_equipe());
create policy dono_edita on horarios_trabalho for all to authenticated using (eh_dono()) with check (eh_dono());
create policy equipe_le on formas_pagamento for select to authenticated using (eh_equipe());
create policy dono_edita on formas_pagamento for all to authenticated using (eh_dono()) with check (eh_dono());
create policy equipe_le on configuracoes for select to authenticated using (eh_equipe());
create policy dono_edita on configuracoes for all to authenticated using (eh_dono()) with check (eh_dono());
create policy equipe_le on planos for select to authenticated using (eh_equipe());
create policy dono_edita on planos for all to authenticated using (eh_dono()) with check (eh_dono());

create policy proprio_ou_dono on perfis for select to authenticated using (id = auth.uid() or eh_dono());
create policy dono_edita on perfis for all to authenticated using (eh_dono()) with check (eh_dono());

-- Agenda: barbeiro vê só a dele, dono vê tudo. Escrita só pelas funções.
create policy barbeiro_ou_dono on agendamentos for select to authenticated
  using (eh_dono() or barbeiro_id = barbeiro_atual());
create policy barbeiro_ou_dono on agendamento_servicos for select to authenticated
  using (exists (select 1 from agendamentos a where a.id = agendamento_id
                 and (eh_dono() or a.barbeiro_id = barbeiro_atual())));
create policy equipe_le on bloqueios for select to authenticated using (eh_equipe());

-- Clientes: barbeiro vê só quem já marcou com ele
create policy barbeiro_ou_dono on clientes for select to authenticated
  using (eh_dono() or exists (select 1 from agendamentos a
                              where a.cliente_id = clientes.id and a.barbeiro_id = barbeiro_atual()));
create policy dono_edita on clientes for update to authenticated using (eh_dono()) with check (eh_dono());

-- Financeiro: só o dono (barbeiro vê os próprios atendimentos)
create policy barbeiro_ou_dono on atendimentos for select to authenticated
  using (eh_dono() or barbeiro_id = barbeiro_atual());
create policy dono_le on pagamentos for select to authenticated using (eh_dono());
create policy dono_le on caixa_movimentos for select to authenticated using (eh_dono());
create policy dono_le on caixa_dia for select to authenticated using (eh_dono());
create policy dono_edita on assinaturas for all to authenticated using (eh_dono()) with check (eh_dono());
create policy dono_le on usos_plano for select to authenticated using (eh_dono());

-- Permissões de tabela e função
revoke all on all tables in schema public from anon;
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;

grant execute on function
  dados_publicos(),
  dias_disponiveis(uuid[], uuid, integer),
  horarios_livres(uuid[], uuid, date),
  criar_agendamento(uuid[], uuid, timestamptz, text, text, boolean),
  agendamento_por_token(uuid),
  cancelar_por_token(uuid),
  remarcar_por_token(uuid, timestamptz)
to anon;

-- Agenda da equipe atualiza ao vivo (Realtime respeita o RLS)
alter publication supabase_realtime add table agendamentos, bloqueios;
