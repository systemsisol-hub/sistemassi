-- La visibilidad de un documento es una ETIQUETA, no una puerta.
--
-- Cuando cree la columna asumi que INTERNO significaba "no entregarlo". El usuario lo aclaro el
-- 02/09/2026 y la politica es otra: todo lo que hay en el Drive es material interno de la empresa y
-- quien le pregunta a SOL es personal nuestro, asi que ENTREGARLO ES SU FUNCION. La etiqueta sirve
-- para que el asesor sepa que tiene en la mano; lo que decida compartir es su responsabilidad.
--
-- Solo cambia el comentario y el prompt de SOL. El mecanismo nunca retuvo nada: 
-- devolvia todos los documentos desde el primer dia. Lo que estaba mal era como se lo contaba al
-- modelo, y un modelo que lee "interno" puede decidir por su cuenta no entregarlo.
comment on column public.documentos.visibilidad is
  ''Etiqueta para el criterio del asesor, NO una puerta. SOL entrega el enlace siempre: todo el ''
  ''Drive es material interno y quien pregunta es personal de la empresa. COMPARTIBLE es material ''
  ''hecho para mostrarse a un cliente; INTERNO no lo es, y SOL lo anota como dato. Lo que el asesor ''
  ''haga con el enlace es su responsabilidad. Politica confirmada por el usuario el 02/09/2026.'';
