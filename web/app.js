// The placeholder assigned below is replaced by Terraform (infra/frontend.tf, a plain string
// substitution -- not templatefile(), which would collide with this file's own JS
// template-literal syntax) with the Phase 5 Function App's default hostname output. Never
// hardcoded, so it can't drift from the actual deployed API. NOTE: the replace() is a global
// string replace, so the literal placeholder text must appear nowhere else in this file
// (including comments) or it would get silently substituted too.
const API_BASE_URL = "__API_BASE_URL__";
const TODOS_URL = `${API_BASE_URL}/api/todos`;

const form = document.getElementById("create-form");
const titleInput = document.getElementById("new-title");
const list = document.getElementById("todo-list");
const errorEl = document.getElementById("error");

function showError(message) {
  errorEl.textContent = message;
  errorEl.hidden = false;
}

function clearError() {
  errorEl.hidden = true;
  errorEl.textContent = "";
}

async function request(path, options) {
  const response = await fetch(path, options);
  if (!response.ok) {
    let detail = "";
    try {
      const body = await response.json();
      detail = body.error || "";
    } catch {
      // no JSON body (e.g. 404 with no payload) -- ignore
    }
    throw new Error(detail || `Request failed (${response.status})`);
  }
  if (response.status === 204) {
    return null;
  }
  return response.json();
}

function renderTodos(todos) {
  list.innerHTML = "";

  if (todos.length === 0) {
    const empty = document.createElement("li");
    empty.className = "empty";
    empty.textContent = "No todos yet.";
    list.appendChild(empty);
    return;
  }

  for (const todo of todos) {
    list.appendChild(renderTodoItem(todo));
  }
}

function renderTodoItem(todo) {
  const item = document.createElement("li");
  item.className = "todo-item" + (todo.is_completed ? " completed" : "");
  item.dataset.id = todo.id;

  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  checkbox.checked = todo.is_completed;
  checkbox.addEventListener("change", () => toggleTodo(todo));

  const title = document.createElement("span");
  title.className = "title";
  title.textContent = todo.title;
  title.title = "Click to edit";
  title.addEventListener("click", () => editTodo(todo));

  const deleteBtn = document.createElement("button");
  deleteBtn.type = "button";
  deleteBtn.setAttribute("aria-label", "Delete");
  deleteBtn.textContent = "×";
  deleteBtn.addEventListener("click", () => deleteTodo(todo));

  item.append(checkbox, title, deleteBtn);
  return item;
}

async function loadTodos() {
  clearError();
  try {
    const todos = await request(TODOS_URL);
    renderTodos(todos);
  } catch (err) {
    showError(`Couldn't load todos: ${err.message}`);
  }
}

async function createTodo(title) {
  clearError();
  try {
    await request(TODOS_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title }),
    });
    await loadTodos();
  } catch (err) {
    showError(`Couldn't create todo: ${err.message}`);
  }
}

async function toggleTodo(todo) {
  clearError();
  try {
    await request(`${TODOS_URL}/${todo.id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ is_completed: !todo.is_completed }),
    });
    await loadTodos();
  } catch (err) {
    showError(`Couldn't update todo: ${err.message}`);
  }
}

async function editTodo(todo) {
  const newTitle = window.prompt("Edit todo", todo.title);
  if (newTitle === null || newTitle.trim() === todo.title.trim()) {
    return;
  }
  clearError();
  try {
    await request(`${TODOS_URL}/${todo.id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: newTitle }),
    });
    await loadTodos();
  } catch (err) {
    showError(`Couldn't update todo: ${err.message}`);
  }
}

async function deleteTodo(todo) {
  clearError();
  try {
    await request(`${TODOS_URL}/${todo.id}`, { method: "DELETE" });
    await loadTodos();
  } catch (err) {
    showError(`Couldn't delete todo: ${err.message}`);
  }
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const title = titleInput.value.trim();
  if (!title) {
    return;
  }
  titleInput.value = "";
  createTodo(title);
});

loadTodos();
