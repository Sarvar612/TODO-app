create database todoapp;
create schema auth;
create schema category;
create schema utils;
create schema todo;


-- setting path!
set search_path to auth;
set search_path to category;
set search_path to utils;
set search_path to todo;



-- Auth
create type authrole as enum('USER','ADMIN');
create table authuser(    id serial primary key,
    username varchar unique not null
        constraint username_valid_length_check check ( length(username) > 4 ),
    password varchar unique not null,    role authrole default 'USER' not null,
    created_at timestamp default current_timestamp not null);

create function auth_register(uname varchar, pswd varchar) returns int language plpgsql
    as $$
    declare        newID int;
    begin        insert into auth.authuser(username, password) values (uname,pswd)
        returning id into newID;        return newID;
    end    $$;
select auth_register('Sarvar','123');
select * from auth.authuser;



--Utils
-- Setting extensions in utils; Utils are used to be as a extensional library;
set search_path to utils;
create extension pgcrypto;

create function encode_password(password varchar) returns varchar
    language plpgsql
    as
    $$
    begin
        return utils.crypt(password,utils.gen_salt('bf',4));

    end$$;
create function match_password(password varchar,encoded_password varchar) returns boolean language plpgsql
as $$declare
    begin
    return encoded_password= utils.crypt(password,encoded_password);
    end $$;

create type language as enum ('UZ','RU','EN');

alter table auth.authuser add column language auth.language default 'UZ' not null;

set search_path to auth;
select auth_register('dilshod','123');
select * from auth.authuser;


create function auth_login(uname varchar,password varchar) returns text language plpgsql
as $$
    declare
        t_auth_user record;
        begin
        select * into t_auth_user from auth.authuser where lower(username) = lower(uname);
        if not FOUND then
            raise exception 'User % not found',uname;
        end if;

        case
            when t_auth_user.language = 'UZ' then
            return json_build_object(
            'Id:',t_auth_user.id,
            'Foydanaluvchi nomi:',t_auth_user.username,
            'Rol:',t_auth_user.role,
            'Registratsiya vaqti:',t_auth_user.created_at,
            'Til:',t_auth_user.language
            )::text;
            when t_auth_user.language='RU' then
            return json_build_object(
            'Ид код:',t_auth_user.id,
            'Имя пользователя:',t_auth_user.username,
            'Роль:',t_auth_user.role,
            'Время регистрации:',t_auth_user.created_at,
            'Язык:',t_auth_user.language
            )::text;
            when t_auth_user.language='EN' then
            return json_build_object(
            'Id:',t_auth_user.id,
            'Username:',t_auth_user.username,
            'Role:',t_auth_user.role,
            'Created Time:',t_auth_user.created_at,
            'Language:',t_auth_user.language
            )::text;
         end case;
        end $$;



select auth_login('Sarvar','123');


-- Category
set search_path to category;

create table category(
    id serial                                        not null,
    title varchar                                    not null,
    user_id int                                      not null,
    created_time timestamp default current_timestamp not null,
    primary key(id),
    foreign key (user_id) references auth.authuser(id) on delete cascade
);



create function create_category(title varchar, sessionuserid int) returns int language plpgsql
as
$$declare
    t_auth_user record;
    newId int;
begin
    select * into t_auth_user from auth.authuser a where a.id=sessionuserid;
    if not FOUND then
        raise exception 'User not found: %',sessionuserid;
    end if;
    insert into category.category(title, user_id) values (title,sessionuserid) returning id into newId;
    return newId;
end
$$;

create function delete_category(category_id int, sessionuserid int) returns int language plpgsql
as
$$declare
    t_auth_user record;
    t_category_id record;
begin
    select * into t_auth_user from auth.authuser a where a.id=sessionuserid;
    if not FOUND then
        raise exception 'User not found: "%"',sessionuserid;
    end if;
    if sessionuserid <> t_auth_user.id then
        raise exception 'Permission denied!';
    end if;
    select * into t_category_id from category.category b where b.id=category_id;
    if not FOUND then
        raise exception 'Category number "%" not found',category_id;
    end if;
    delete from category.category where category_id=t_category_id.id;
end
$$;

select create_category('Gym',2);
select delete_category(18,2);

select * from category;

set search_path to auth;
create procedure isactive(userid int)
    language plpgsql as
    $$declare
        begin
        if not exists(select * from auth.authuser a where a.id=userid) then
            raise exception 'User not found!';
        end if;

        end $$;
-- AUTH
set search_path to auth;
create function role(role auth.authrole,userid int) returns boolean language plpgsql
    as
    $$declare
        t_auth_user record;
        begin
        select * into t_auth_user from auth.authuser a where a.id =userid;

        if FOUND then
            return auth.authuser.role=role;
        else
            return false;
        end if;
        end $$;




set search_path to category;
select create_category('Gym',3);
select create_category('Reading',3);
select create_category('Swimming',3);
select create_category('Football',3);

select * from category;

select delete_category(18,2);

set search_path to todo;

create type priority as enum ('LOW','MEDIUM','HIGH','DEFAULT');


--TODO
create table todo(
    id serial,
    title varchar not null ,
    description varchar,
    priority todo.priority default 'DEFAULT' not null,
    category_id int,
    created_time timestamp default current_timestamp not null,
    due_time date,
    primary key (id),
    foreign key (category_id) references category.category(id)
);


set search_path to todo;


create function create_todo(dataparam text, userid integer) returns int
    language plpgsql
as
$$declare
    dataJson json;
    newId int;
    begin

    call auth.isactive(userid);

    if dataparam is null then
        raise exception 'Invalid data parameters';
    end if;

    if not exists(select * from category.category c where c.id=dataJson ->> ('category_id')::int) then
        raise exception 'Category "%" not found!',dataJson ->> ('category_id')::int;
    end if;

    dataJson := dataparam::json;

    insert into todo.todo(title, description, priority, category_id, due_time)
    values (
            dataJson ->> 'title',
            dataJson ->> 'description',
            (dataJson ->> 'priority')::todo.priority,
            (dataJson ->> 'category_id')::int,
            (dataJson ->> 'due_time')::date
           ) returning id into newId;
    return newId;
    end $$;

select create_todo('{
  "title": "Read about magician",
  "description":"Hello mth",
  "priority":"HIGH",
  "category_id": 17
}',3);

select * from todo;

create type todo_dto as (
    title varchar,
    description varchar,
    priority todo.priority,
    category_id int,
    due_time date
);

alter table todo add column is_done boolean default false not null;


create function update_todo(dataparam text, userid integer) returns int
    language plpgsql
as
$$declare
    t_todo record;
    t_category record;
    dataJson json;
    dto todo.update_todo_dto;
    begin
    call auth.isactive(userid);

    if dataparam is null then
        raise exception 'Invalid data parameters';
    end if;

    dto.id := dataJson->> 'id';
    dataJson := dataparam::json;

    select * into t_todo from todo.todo t where t.id=dto.id;

    if not FOUND then
        raise exception 'TODO "%" not found',dto.id;
    end if;

    select * into t_category from category.category a where a.id=t_todo.category_id;

    if not FOUND or t_category.user_id <> userid then
        raise exception 'Permission denied!';
    end if;

    dto.title := (dataJson ->> 'title',t_todo.title);
    dto.priority := coalesce(dataJson ->> 'priority', t_todo.priority::text);
    dto.description := coalesce(dataJson ->> 'description',t_todo.description);
    dto.due_time := coalesce(dataJson ->> 'due_time',t_todo.due_time::text);
    dto.is_done := coalesce(dataJson ->> 'is_done',t_todo.is_done::text);


    update todo.todo
    set title = dto.title,
        description = dto.description,
        priority = dto.priority,
        is_done = dto.is_done where id=dto.id;

    return true;
    end $$;


create type update_todo_dto as (
    id int,
    title varchar,
    description varchar,
    priority todo.priority,
    category_id int,
    due_time date,
    is_done boolean
);

select * from todo;

select update_todo('{
    "id": 4 ,
    "priority":"LOW"
}',3);


create function user_todos_by_category(userid int) returns  text language plpgsql
as
$$declare
    begin
    call auth.isactive(userid);

    return (select json_agg( json_build_object(
        'category_id',category_id,
        'category_name',category_name,
        'user_id',user_id,
        'todos',todos))
          from (select t.category_id,
                       c.title category_name,
                       c.user_id,
                       json_agg(

                        json_build_object(
                        'id',t.id,
                        'title',t.title,
                        'description',t.description,
                        'due_date',t.due_time,
                        'priority',t.priority,
                        'is_done',t.is_done,
                        'created_at',t.created_time
                        )
        ) as todos
    from todo t
        inner join category.category c on c.id = t.category_id
    group by t.category_id,c.title,c.user_id) as category_details)::text;
    end $$;

select t.*,c.title from todo.todo t
inner join category.category c on t.category_id=c.id
where c.user_id=3;

set search_path to exceptions;

select todo.user_todos_by_category(2);


select todo.update_todo('{"id":2, "title":"Supermen"}',7);
select * from todo.todo;


create procedure permission(userid int,userid2 int) language plpgsql
as
$$  declare
    t_auth record;
    begin
    select * into t_auth from auth.authuser a where a.id=userid;
        if userid <> userid2 then
            case
                when t_auth.language='UZ' then
                raise exception 'Ruxsat berilmadi!';
                when t_auth.language='EN' then
                raise exception 'Permission denied!';
                when t_auth.language='RU' then
                raise exception 'Разрешение отклонено!';
            end case;
        end if;
    end $$;

