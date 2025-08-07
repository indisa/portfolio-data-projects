/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:

SELECT COUNT(payer) AS all_users, -- все игроки
	SUM(payer) AS paying_users, -- платящие игроки
	ROUND(AVG(payer)::NUMERIC,2) AS share_paying_users-- среднее число
FROM fantasy.users
ORDER BY all_users; 


-- 1.2. Доля платящих пользователей в разрезе расы персонажа:

SELECT race,
	COUNT(DISTINCT id) AS all_users, --все игроки
	SUM(payer) AS paying_users, --платящие игроки
	ROUND(SUM(payer)::numeric/COUNT(DISTINCT id),2) AS share_paying_users --доля платящих пользователей от общего числа
FROM fantasy.users u
LEFT JOIN fantasy.race r USING(race_id)
GROUP BY race
ORDER BY share_paying_users desc;


-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
SELECT COUNT(transaction_id) AS count_transaction, --количество покупок
		SUM(amount) AS sum_amount, --общая сумма покупок
		MIN(amount) AS min_amount, --минимальная сумма покупки
		MAX(amount) AS max_amount, --максимальная сумма покупки
		ROUND(AVG(amount)::numeric, 2) AS avg_amount, -- средняя сумма покупки
		percentile_disc(0.50) WITHIN GROUP (ORDER BY amount) AS mid_amount, -- медиана
		ROUND(stddev(amount)::numeric,2) AS stddev_amount -- размах
FROM fantasy.events e
WHERE amount>0;

-- 2.2: Аномальные нулевые покупки:
--Укороченная версия:
SELECT (SELECT COUNT(amount) FROM fantasy.events), --общее количество транзакций
	COUNT(amount) AS null_amount, --количество минимальных значений
	ROUND(COUNT(amount) / (SELECT COUNT(amount) FROM fantasy.events)::NUMERIC,3) AS share_null_amount -- доля в транзакциях
FROM fantasy.events 
WHERE amount = 0; 

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
--Укороченная версия:
SELECT payer, -- платящие (1) и неплатящие(0) игроки
	COUNT(DISTINCT id) AS count_users, --количество игроков
	COUNT(transaction_id) AS count_trans, --общее количество транзакций
	ROUND(COUNT(transaction_id)/COUNT(DISTINCT id)::NUMERIC,2) AS avg_trans, -- среднее число покупок на игрока
	ROUND(SUM(amount)::numeric/COUNT(DISTINCT id),2) AS avg_amount -- средняя сумма покупки на одного игрока
FROM fantasy.users u 
RIGHT JOIN fantasy.events e USING(id) -- исправлен способ присоединения
GROUP BY payer;

-- 2.4: Популярные эпические предметы:
SELECT item_code,
	game_items,
	COUNT(transaction_id) AS count_purchases, -- количество покупок
	ROUND(COUNT(transaction_id)::numeric/(SELECT count(transaction_id) FROM fantasy.events), 3) AS relative_purchases, -- доля покупок от общего числа
	ROUND(COUNT(DISTINCT id)::numeric/(SELECT COUNT(DISTINCT id) FROM fantasy.events e2), 2) AS relative_count_users, -- доля покупателей от общего числа игроков, совершавших покупки
	ROW_NUMBER() OVER(ORDER BY COUNT(transaction_id) DESC) -- номера позиции для анализа
FROM fantasy.items i 
LEFT JOIN fantasy.events e USING(item_code) 
GROUP BY item_code, game_items
ORDER BY count_purchases DESC;

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
-- Все игроки по расам:
WITH all_users AS 
(SELECT race_id, race,
	COUNT(DISTINCT id) AS count_all_u
FROM fantasy.users u
LEFT JOIN fantasy.race r USING(race_id)
GROUP BY race_id, race),
--Игроки, совершившие покупку:
purshasing_users AS 
(SELECT race_id, race,
	COUNT(DISTINCT id) AS count_purshasing_u
FROM 
	(SELECT id,
		COUNT(transaction_id) AS count_t
	FROM fantasy.users u
	LEFT JOIN fantasy.events e USING(id)
	GROUP BY id) AS trans_users
LEFT JOIN fantasy.users u USING(id)
LEFT JOIN fantasy.race r USING(race_id)
WHERE count_t>0 
GROUP BY race_id, race),
--Платящие игроки:
paying_users AS 
(SELECT race_id, race,
	COUNT(DISTINCT id) AS count_paying_u
FROM fantasy.users u
LEFT JOIN fantasy.race r USING(race_id)
WHERE payer=1 AND id IN(SELECT DISTINCT id FROM fantasy.events e)
GROUP BY race_id, race),
--Доля платящих игроков от совершивших покупку:
share_paying_users AS 
(SELECT race_id, race,
	ROUND(count_paying_u::numeric/count_purshasing_u,2) AS share_paying_u
FROM purshasing_users pu
LEFT JOIN paying_users USING(race_id, race)
GROUP BY race_id, race, count_paying_u, count_purshasing_u),
--Подсчеты:
activity_users AS 
(SELECT race_id, race,
	ROUND(COUNT(DISTINCT e.transaction_id)::NUMERIC/count_purshasing_u,2) AS avg_purshases,
	ROUND(SUM(amount)::NUMERIC/COUNT(DISTINCT e.transaction_id),2) AS avg_amount_transaction,
	ROUND(SUM(amount)::NUMERIC/count_purshasing_u,2) AS avg_amount_u
FROM fantasy.users u 
LEFT JOIN fantasy.events e USING(id)
LEFT JOIN purshasing_users pu USING(race_id)
WHERE amount>0
GROUP BY race_id, race, count_purshasing_u)
SELECT race_id, race, 
	count_all_u, -- общее количество игроков
	count_purshasing_u, --количество игроков, совершивших покупку
	ROUND(count_purshasing_u::numeric/count_all_u,2) AS share_purchasing_u, --доля платящих игроков от общего количества (добавлено)
	count_paying_u, -- платящие игроки
	share_paying_u, --доля платящих игроков от игроков, совершивших покупку
	avg_purshases, --среднее количество покупок на одного игрока
	avg_amount_transaction, --средняя стоимость одной покупки на одного игрока
	avg_amount_u-- средняя суммарная стоимость всех покупок на одного игрока
FROM all_users
LEFT JOIN purshasing_users USING(race_id, race)
LEFT JOIN paying_users USING(race_id, race)
LEFT JOIN share_paying_users USING(race_id, race)
LEFT JOIN activity_users USING(race_id, race)
ORDER BY avg_purshases DESC;

-- Задача 2: Частота покупок
--Количество дней с предыдущей покупки (кроме нулевых покупок):
WITH transaction_gap AS
(SELECT transaction_id,
	id,
	e.date::date,
	LAG(date) OVER(PARTITION BY id ORDER BY date) AS previous_transaction,
	(e.date::date-(LAG(date) OVER(PARTITION BY id ORDER BY date)::date)) AS gap
FROM fantasy.events e
WHERE amount>0),
--Количество покупок на игрока и средний геп между покупками:
users_pay AS
(SELECT tg.id,
	u.payer,
	COUNT(DISTINCT transaction_id) AS count_transactions,
	AVG(gap) AS avg_gap
FROM transaction_gap tg
LEFT JOIN fantasy.users u ON u.id=tg.id
GROUP BY tg.id, u.payer
ORDER BY tg.id),
--Ранжирование игроков по гепу между покупками с учетом количества покупок:
rank_users_1 AS 
(SELECT id,
	payer,
	avg_gap,
	NTILE(3) OVER(ORDER BY avg_gap) AS parts_by_gap
FROM users_pay
WHERE count_transactions>=25),
rank_users_2 AS 
(SELECT id, 
	payer,
	avg_gap,
	CASE 
		WHEN parts_by_gap=1 THEN 'высокая частота'
		WHEN parts_by_gap=2 THEN 'умеренная частота'
		WHEN parts_by_gap=3 THEN 'низкая частота'
	END AS users_group
FROM rank_users_1),
--Платящие игроки
paying_users AS
(SELECT id
FROM rank_users_2
WHERE payer=1)
SELECT users_group,
	COUNT(DISTINCT ru.id) AS count_users, --количество игроков;
	COUNT(DISTINCT pu.id) AS paying_users,-- количество платящих игроков, совершивших покупки;
	ROUND(COUNT(DISTINCT pu.id)/COUNT(DISTINCT ru.id)::NUMERIC, 2) AS share_paying_users, --доля платящих игроков от общего количества;
	ROUND(COUNT(DISTINCT tg.transaction_id)::NUMERIC/COUNT(DISTINCT ru.id)::NUMERIC,2) AS count_transaction, -- количество покупок на одного игрока;
	ROUND(AVG(avg_gap)) AS avg_gap -- среднее количество дней между покупками на одного игрока;
FROM rank_users_2 ru
LEFT JOIN paying_users pu ON ru.id=pu.id
LEFT JOIN transaction_gap tg ON ru.id=tg.id
GROUP BY users_group
ORDER BY avg_gap;
