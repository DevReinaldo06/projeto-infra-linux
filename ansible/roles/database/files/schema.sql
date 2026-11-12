CREATE TABLE IF NOT EXISTS public.registros (
    id serial PRIMARY KEY,
    nome varchar(80) NOT NULL,
    mensagem varchar(500) NOT NULL,
    criado_em timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT ON TABLE public.registros TO app_user;
GRANT SELECT ON TABLE public.registros TO analista_dados;
GRANT SELECT, USAGE ON SEQUENCE public.registros_id_seq TO app_user;
