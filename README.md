# Dimensional Data Modeling
## Cumulative Data

Data modeling can be summarized as a process to transform transactional data into analytical data. Its main purpose is to organize information coming from one or more sources in a more query-friendly manner, building context-specific structures. 

There are two main architectures used to build data warehouses: Star-schema and Snowflake. In a quick comparison, the first one brings denormalization (some level of redundancy) and optimization focused on query performance, while the latter is based on hierarchical sub-dimensions, prioritizing normalization, storage space, and governance. While star-schema prioritizes speed, simplicity, and user accessibility, Snowflake can better handle strict governance, have minimal redundancy, and pay the cost of complexity with its hierarchical relationships. In order to better explore dimensional data modeling, this article will focus on the star-schema architecture.

It is composed by one (or a few) central fact table linked directly to denormalized dimension tables, which form a star-like structure (therefore star-schema). By avoiding normalization, star-schemas minimize join operations, enabling faster querying. However, it also introduces redundancy, which means repeated attributes in different tables and, hence, more storage requirements. The main advantage is simplifying data exploration for business analytics as queries often involve straightforward joins, making it easier for analytical tools to rapidly aggregate metrics and filter on attributes. 

Fact tables store information about something that happened, like a transaction made. For this reason, they are usually larger in volume and can need a lot of business context to be understood. They can also be recognized as the Who, What, Where, When and How table, including fields regarding id’s, actions, timestamps, and even metrics.

Dimensions are descriptive attributes of an entity, and are responsible for characterizing the observations found in the fact table with more details. For example, in a retail scenario, dimension tables of customers and products might connect with a fact table of sales or orders. That way, by joining the fact table, which also stores the necessary foreign keys, to the dimension tables, it is possible to paint a more detailed image on which products were sold, which brand are they manufactured by, who are the clients buying them and so on.

Besides storing characteristics and attributes, dimensional modeling can also be used to create an aggregation around state transition. For example, websites or social networks need to know whether a user was active at a certain point in time. Instead of going through all the observations of a fact table (which will have a much larger volume) and pinpoint the days when they were active, it is possible to aggregate a dimension based on user activity and drastically reduce cardinality for querying. This is called a cumulative table design, and is based on a full outer join of two dataframes (for today and yesterday), a coalesce function to keep the most complete data, and computing cumulative metrics by combining arrays and changing values. Another use case is for keeping track of growth.  

Here is an example of how this approach can be implemented (also shown in a Bootcamp by Zack Wilson):

Starting from an NBA transactional table that stores data for player statistics throughout a number of seasons, the idea is to aggregate the main information by player name and reduce cardinality from player and season to player alone. 

![Table columns](caminho-da-imagem.png)

![Table preview](caminho-da-imagem.png)

The first step is to select what information should be important when looking at a player’s season. Besides characteristics that identify and describe the player (such as name, height, college, and draft info), for simplification purposes, the attributes that will be used to summarize a player’s season are the average number of points, assists and rebounds per game. They will be stored in an array-based type we’ll call season_stats:

```sql
create type season_stats as (
	season integer,
	pts real,
	ast real,
	reb real
);
```
Another information that can be useful is knowing whether a player had a good season. There are many ways to define what a good season should look like, but again for simplification purposes, let’s just say that the average points per game can be an indicator of a good season. In order to create a field and be certain that it will always hold the same values (in this case, categories), we will also create an enum based type called scoring_class:

```sql
CREATE TYPE scoring_class AS
     ENUM ('bad', 'average', 'good', 'star');
```

There are two more columns we can create based on the transactional game data: one to define if a player is active in a given season, and one to define the number of seasons since the player's last appearance. Of course, if a player is active, the latter will be 0. But if we’re looking at historical data, this information may come in handy.

Finally, the last field is used to identify our reference date, which in this case is the year of the season we are interested in. This way, besides keeping track of history, we also guarantee snapshots of the seasons if we need to recreate a view of a certain point in time. For example, we might be in 2025, but if I wanted to look at the picture based on what data was available in 2001, it is possible to filter by current season and access this view. Our final query to create the table looks like [this](xxx.sql).

Now that the table is created, we need to populate it. The idea here is to start from the first year we need information from and build up on that. Also, we need to explicit the terms for the scoring_class categories, which in this case will be defined in slices of the points per game value. As we are basing this [first insert](yyy.sql) on a specific season, every player will be active.

The next step is to create a pipeline out of this. The example below considers a yearly timespan, but the logic should suffice to address other types of cases, such as in daily batch processes. As aforementioned, the main idea is to use a full outer join to merge data season by season so that the whole history of players will be recorded, including their first and last appearances. 

To start, we can use the original table to create a CTE for the next season (this_season) and use the first insert in the new table as our historical data (last_season). Then, it is just a series of coalesce functions in order to consider both sides of the full outer join as reference for the observation. For example, coalesce will ensure that player name (and the other player attributes) will always be filled: it will check for a name in this_season and, in case it is null, it will bring information from last_season.

For the calculated fields, the idea is basically the same, but the execution varies a little bit. Our goal is to update data depending on whether we are talking about a new player (first appearance is in this_season), a player who is in both the historical (last_season) and this_season data, or a player who is only in the historical data (not playing the current season).

The season_stats field is the trickiest one because we store all the historical data in one array. So, in case it is a new player (season_stats for this_season is null), we only need to bring in data from this_season. When we do have historical data and also new data coming in (both this_season and last_season season_stats are not null), we need to append new data in the array. And when we only have historical data (season_stats for this_season is null), all we need to do is retrieve it.

For scoring_class, if there is new data for this_season, we bring it. Otherwise, just fill it with last_season data. For the is_active flag, the same logic applies: if there is data for this_season, the player is active, otherwise they are not.

Finally, for years_since_last_season, if there is data for this_season, it should return zero. Otherwise, we need to check last_season data for the latest season appearance. We can do that by extracting this value from the seasons field (our array with the whole history) using the cardinality function. Then, we just take the current season based on last_season data (since we do not find this player in this_season), which translates to last_season.current_season + 1, and deduct the value we found for the last appearance. For example, if we are building this table using 2001 as this_season and 2000 as last_season, and the last appearance of the player was in 1998, the calculation will end up as: (2000 + 1) - 1998 = 3. So the conclusion is that the player’s last appearance was 3 years ago.

The final table will look like this:
![Final cumulative table](caminho-da-imagem.png)

We can see that the seasons field is populated by arrays that store data from each season, starting in 1996. The number of values are an indicator of the number of seasons in which a certain player has been active. So, for every season, the whole history of a player is contained in one row, reaching our initial goal of reducing data cardinality while maintaining all analytical data needed. 
