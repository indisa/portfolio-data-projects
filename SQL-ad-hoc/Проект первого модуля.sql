/* Проект первого модуля: анализ данных для агентства недвижимости
 * Решаем ad hoc задачи
 * 
*/

-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits) OR balcony IS NULL)
    ),
-- Разделим объявления на 4 группы по количеству дней в продаже и на две группы по области:
group_by_days AS (
	SELECT DISTINCT id,
		CASE 
		WHEN days_exposition < 30 THEN 'month'
		WHEN days_exposition >=30 AND days_exposition <= 90 THEN 'quarter'
		WHEN days_exposition > 90 AND days_exposition <= 180 THEN 'half_year'
		WHEN days_exposition > 180 THEN 'more'
		ELSE 'other' -- объявления, у которых не указано время активности (не проданные)
	END AS days_category,
	CASE 
		WHEN city='Санкт-Петербург' THEN 'Санкт-Петербург'
		ELSE 'Область'
	END AS city_category
	FROM real_estate.advertisement a
	LEFT JOIN real_estate.flats f USING(id)
	LEFT JOIN real_estate.city c USING(city_id)
	WHERE id IN (SELECT * FROM filtered_id) -- фильтрация аномальных значений
	)
-- Основные расчеты:
SELECT days_category,
	city_category, -- группировки по категориям
	COUNT(DISTINCT f.id) AS count_id, -- количество объявлений
	ROUND(AVG(last_price/total_area)::NUMERIC,2) AS avg_price_meter, -- средняя цена за метр
	ROUND(AVG(total_area)::NUMERIC,2) AS avg_area, -- средняя площадь
	PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY rooms) AS mid_rooms, -- медиана количества комнат
	PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY balcony) AS mid_balcony, -- медиана балконов
	PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY floor) AS mid_floor -- медиана этажа
FROM group_by_days g
LEFT JOIN real_estate.flats f USING(id)
LEFT JOIN real_estate.type t USING(type_id)
LEFT JOIN real_estate.advertisement a USING(id)
WHERE TYPE='город' -- фильтрация городов
GROUP BY days_category, city_category
ORDER BY city_category DESC;


-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

-- Запрос для объявлений:
-- Выборка:
WITH all_id AS (
	SELECT  DISTINCT id,
			EXTRACT(MONTH FROM first_day_exposition) AS month_exposition
	FROM real_estate.advertisement a
	LEFT JOIN real_estate.flats f USING(id)
	LEFT JOIN real_estate."type" t USING(type_id)
	WHERE first_day_exposition >= '01.01.2015' 
		AND first_day_exposition < '01.01.2019'
		AND TYPE='город'
	)
-- Расчеты и ранжирование:
SELECT RANK () OVER(ORDER BY COUNT(DISTINCT id) desc) AS rank_expositions, -- ранжирование по количеству объявлений
	month_exposition,
	COUNT(DISTINCT id) AS count_saled,
	ROUND(AVG(last_price/total_area)::NUMERIC,2) AS avg_price_meter, -- средняя цена за метр
	ROUND(AVG(total_area)::NUMERIC,2) AS avg_area -- средняя площадь
FROM all_id ai
LEFT JOIN real_estate.flats f USING(id)
LEFT JOIN real_estate.advertisement a USING (id)
LEFT JOIN real_estate."type" t USING(type_id)
GROUP BY month_exposition

-- Запрос для продаж:
-- Выборка:
WITH saled AS (
	SELECT DISTINCT id,
		(first_day_exposition + INTERVAL'1 day' * days_exposition)::date AS last_day_exposition -- дата продажи
	FROM real_estate.advertisement a 
	),
all_exp AS (
	SELECT  DISTINCT id,
			EXTRACT(MONTH FROM last_day_exposition) AS month_sale_exposition
	FROM saled
	LEFT JOIN real_estate.flats f USING(id)
	LEFT JOIN real_estate."type" t USING(type_id)
	WHERE last_day_exposition >= '01.01.2017' 
		AND last_day_exposition < '01.01.2019'
		AND TYPE='город'
	)
-- Расчеты и ранжирование:
SELECT RANK () OVER(ORDER BY COUNT(DISTINCT id) desc) AS rank_saled, -- ранжирование по количеству объявлений
	month_sale_exposition,
	COUNT(DISTINCT id) AS count_saled,
	ROUND(COUNT(id)/(
	SELECT COUNT(DISTINCT id)
	FROM real_estate.advertisement a 
	LEFT JOIN real_estate.flats f USING(id)
	LEFT JOIN real_estate."type" t USING(type_id)
	WHERE first_day_exposition >= '01.01.2017' 
		AND first_day_exposition < '01.01.2019'
		AND TYPE='город')::NUMERIC, 2) AS share_saled, -- доля проданных объявлений к общему количеству
	ROUND(AVG(last_price/total_area)::NUMERIC,2) AS avg_price_meter, -- средняя цена за метр
	ROUND(AVG(total_area)::NUMERIC,2) AS avg_area -- средняя площадь
FROM all_exp ae
LEFT JOIN real_estate.flats f USING(id)
LEFT JOIN real_estate.advertisement a USING (id)
LEFT JOIN real_estate."type" t USING(type_id)
GROUP BY month_sale_exposition


-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

-- Топ городов по объявлениям:
WITH top_city AS (
	SELECT city,
		count(id)
	FROM real_estate.flats f 
	LEFT JOIN real_estate.city c USING(city_id)
	GROUP BY city
	HAVING count(id) > 130 AND city!='Санкт-Петербург'-- топ 15 городов
	ORDER BY count(id) DESC
	),
-- Объявления, снятые с продажи (проданные):
saled AS 
	(SELECT DISTINCT id AS saled_flats
	FROM real_estate.advertisement a
	WHERE days_exposition IS NOT NULL
	)
-- Общие расчеты:
SELECT city,
	count(DISTINCT id) AS count_exppositions, -- количество объявлений
	ROUND(count(s.saled_flats)/count(DISTINCT id)::NUMERIC, 2) AS share_saled, -- доля снятых с продажи квартир
	ROUND(AVG(last_price/total_area)::NUMERIC,2) AS avg_price_meter, -- средняя цена за метр
	ROUND(AVG(total_area)::NUMERIC,2) AS avg_area, -- средняя площадь
	ROUND(AVG(days_exposition)::NUMERIC,2) AS avg_duration_exp -- длительность объявления
FROM real_estate.flats f 
LEFT JOIN real_estate.advertisement a USING(id)
LEFT JOIN real_estate.city c USING(city_id)
LEFT JOIN saled s ON s.saled_flats=f.id
WHERE city IN (SELECT city FROM top_city)
GROUP BY city
ORDER BY count_exppositions DESC;