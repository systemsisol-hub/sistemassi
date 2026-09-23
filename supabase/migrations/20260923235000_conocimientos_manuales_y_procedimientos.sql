-- Conocimientos: la categoría «Procedimientos» pasa a llamarse «Manuales y Procedimientos».
--
-- Pedido del usuario el 23/09/2026. La categoría se guarda como TEXTO en cada artículo, no por un id,
-- así que cambiar el nombre en la pantalla no basta: el artículo que ya estaba en «Procedimientos»
-- dejaría de salir al filtrar por la categoría nueva, y perdería su icono y su color.
--
-- Se aplica JUNTO con la subida a producción de la pantalla que ya trae el nombre nuevo. Antes, la
-- pantalla de producción no reconocería la categoría; después, la de producción no reconocería la
-- vieja.

update public.knowledge_articles
   set category = 'Manuales y Procedimientos'
 where category = 'Procedimientos';
