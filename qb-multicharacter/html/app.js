/**
 * VGX Multicharacter — sharp cyber UI (vanilla JS, no Vue/Vuetify)
 */

const RESOURCE = typeof GetParentResourceName === "function" ? GetParentResourceName() : "qb-multicharacter";

const post = (endpoint, data) => axios.post(`https://${RESOURCE}/${endpoint}`, data || {});

const $ = (id) => document.getElementById(id);

const state = {
    characters: [],
    characterAmount: 0,
    selectedSlot: -1,
    allowDelete: false,
    customNationality: false,
    nationalities: [],
    gender: null,
};

const moneyFormat = Intl.NumberFormat("en-US");

const t = (key, params) => (params ? translationManager.formatTranslation(key, params) : translationManager.translate(key));

/*------------------------------------*\
  SCREEN HELPERS
\*------------------------------------*/
const show = (id) => $(id).classList.remove("hidden");
const hide = (id) => $(id).classList.add("hidden");

function showApp(visible) {
    document.getElementById("app").classList.toggle("hidden", !visible);
}

/*------------------------------------*\
  TRANSLATION BINDING
\*------------------------------------*/
function applyTranslations() {
    $("t-characters-header").textContent = t("characters_header");
    $("t-charinfo-header").textContent = t("charinfo_header");
    $("t-charinfo-description").textContent = t("charinfo_description");
    $("t-play").textContent = t("play_button");
    $("btn-delete").title = t("delete_button");
    $("t-register-header").textContent = t("chardel_header");
    $("l-firstname").textContent = t("firstname");
    $("l-lastname").textContent = t("lastname");
    $("l-nationality").textContent = t("nationality");
    $("l-gender").textContent = t("gender");
    $("l-birthdate").textContent = t("birthdate");
    $("t-male").textContent = t("male");
    $("t-female").textContent = t("female");
    $("t-create").textContent = t("create_button");
    $("t-deletechar-header").textContent = t("deletechar_header");
    $("t-deletechar-description").textContent = t("deletechar_description");
    $("t-confirm").textContent = t("confirm");
    $("t-cancel").textContent = t("cancel");
    $("toast-title").textContent = t("ran_into_issue");
}

/*------------------------------------*\
  TOAST
\*------------------------------------*/
let toastTimer = null;
function toast(message) {
    $("toast-text").textContent = message;
    show("toast");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => hide("toast"), 4500);
}

/*------------------------------------*\
  SLOT LIST
\*------------------------------------*/
function renderSlots() {
    const list = $("slot-list");
    list.innerHTML = "";

    let used = 0;
    for (let i = 1; i <= state.characterAmount; i++) {
        const char = state.characters[i];
        const card = document.createElement("div");
        card.className = "slot-card" + (char ? "" : " empty") + (state.selectedSlot === i ? " active" : "");

        if (char) {
            used++;
            card.innerHTML = `
                <div class="slot-num">${String(i).padStart(2, "0")}</div>
                <div class="slot-info">
                    <span class="slot-name"></span>
                    <span class="slot-sub"></span>
                </div>`;
            card.querySelector(".slot-name").textContent = `${char.charinfo.firstname} ${char.charinfo.lastname}`;
            card.querySelector(".slot-sub").textContent = char.job && char.job.label ? char.job.label : "";
            card.addEventListener("click", () => selectSlot(i));
        } else {
            card.innerHTML = `
                <div class="slot-plus">+</div>
                <div class="slot-info">
                    <span class="slot-name"></span>
                    <span class="slot-sub">${String(i).padStart(2, "0")}</span>
                </div>`;
            card.querySelector(".slot-name").textContent = t("emptyslot");
            card.addEventListener("click", () => openRegister(i));
        }
        list.appendChild(card);
    }

    $("slot-counter").textContent = `${used} / ${state.characterAmount}`;
}

function detailItem(icon, label, value, extraClass, wide) {
    return `
        <div class="detail-item${wide ? " wide" : ""}">
            <label><span class="material-symbols-outlined">${icon}</span>${label}</label>
            <span class="val${extraClass ? " " + extraClass : ""}">${value}</span>
        </div>`;
}

function esc(v) {
    const d = document.createElement("div");
    d.textContent = v == null ? "—" : String(v);
    return d.innerHTML;
}

function selectSlot(i) {
    state.selectedSlot = i;
    const char = state.characters[i];
    renderSlots();

    // Spawn the preview ped for this character (server-side skin lookup)
    post("cDataPed", { cData: char });

    hide("detail-empty");
    show("detail-body");

    $("detail-fullname").textContent = `${char.charinfo.firstname} ${char.charinfo.lastname}`;
    $("detail-citizenid").textContent = char.citizenid;

    const info = char.charinfo;
    const genderLabel = info.gender === 1 || info.gender === "1" ? t("female") : t("male");

    $("detail-grid").innerHTML =
        detailItem("badge", t("job"), esc(char.job ? char.job.label : "—")) +
        detailItem("military_tech", t("jobgrade"), esc(char.job && char.job.grade ? char.job.grade.name : "—")) +
        detailItem("payments", t("cash"), "$" + moneyFormat.format(char.money.cash || 0), "money") +
        detailItem("account_balance", t("bank"), "$" + moneyFormat.format(char.money.bank || 0), "bank") +
        detailItem("public", t("nationality"), esc(info.nationality)) +
        detailItem("cake", t("birthdate"), esc(info.birthdate)) +
        detailItem("wc", t("gender"), genderLabel) +
        detailItem("call", t("phonenumber"), esc(info.phone)) +
        detailItem("account_balance_wallet", t("accountnumber"), esc(info.account), null, true);

    $("btn-delete").classList.toggle("hidden", !state.allowDelete);
}

function clearDetail() {
    state.selectedSlot = -1;
    show("detail-empty");
    hide("detail-body");
}

/*------------------------------------*\
  REGISTER MODAL
\*------------------------------------*/
function openRegister(slot) {
    state.selectedSlot = slot;
    renderSlots();
    post("cDataPed", {}); // random preview ped for a fresh character

    state.gender = null;
    $("in-firstname").value = "";
    $("in-lastname").value = "";
    $("in-nationality").value = "";
    $("in-birthdate").value = new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().substr(0, 10);
    $("in-birthdate").max = new Date().toISOString().substr(0, 10);
    $("btn-male").classList.remove("active");
    $("btn-female").classList.remove("active");
    hide("nationality-dropdown");
    show("register-screen");
}

function closeRegister() {
    hide("register-screen");
    clearDetail();
    renderSlots();
}

function pickGender(which) {
    state.gender = which;
    $("btn-male").classList.toggle("active", which === "male");
    $("btn-female").classList.toggle("active", which === "female");
}

function createCharacter() {
    const data = {
        firstname: $("in-firstname").value.trim(),
        lastname: $("in-lastname").value.trim(),
        nationality: $("in-nationality").value.trim(),
        gender: state.gender ? t(state.gender) : undefined,
        date: $("in-birthdate").value,
    };

    if (!state.customNationality && data.nationality && !state.nationalities.includes(data.nationality)) {
        toast(t("forgotten_field"));
        return;
    }

    const result = characterValidator.validateCharacter(data);
    if (!result.isValid) {
        toast(t(result.message, { field: t(result.field) }));
        return;
    }

    hide("register-screen");
    hide("select-screen");

    post("createNewCharacter", {
        firstname: data.firstname,
        lastname: data.lastname,
        nationality: data.nationality,
        birthdate: data.date,
        gender: data.gender,
        cid: state.selectedSlot,
    });
}

/*------------------------------------*\
  NATIONALITY AUTOCOMPLETE
\*------------------------------------*/
function setupNationality() {
    const input = $("in-nationality");
    const dropdown = $("nationality-dropdown");

    const render = () => {
        if (state.customNationality) {
            hide("nationality-dropdown");
            return;
        }
        const q = input.value.toLowerCase();
        const matches = state.nationalities.filter((n) => n.toLowerCase().includes(q)).slice(0, 40);
        if (!matches.length) {
            hide("nationality-dropdown");
            return;
        }
        dropdown.innerHTML = "";
        matches.forEach((n) => {
            const item = document.createElement("div");
            item.className = "dropdown-item";
            item.textContent = n;
            item.addEventListener("mousedown", (e) => {
                e.preventDefault();
                input.value = n;
                hide("nationality-dropdown");
            });
            dropdown.appendChild(item);
        });
        show("nationality-dropdown");
    };

    input.addEventListener("input", render);
    input.addEventListener("focus", render);
    input.addEventListener("blur", () => setTimeout(() => hide("nationality-dropdown"), 120));
}

/*------------------------------------*\
  MAIN FLOW
\*------------------------------------*/
function startLoadingSequence() {
    showApp(true);
    hide("select-screen");
    hide("register-screen");
    hide("delete-screen");
    show("loading-screen");

    const steps = ["retrieving_playerdata", "retrieving_playerdata", "retrieving_playerdata", "validating_playerdata", "retrieving_characters", "retrieving_characters", "validating_characters", "validating_characters"];
    let progress = 0;

    $("loader-fill").style.width = "4%";
    $("loading-text").textContent = t(steps[0]);

    const interval = setInterval(() => {
        progress++;
        if (progress < steps.length) {
            $("loading-text").textContent = t(steps[progress]);
        }
        $("loader-fill").style.width = Math.min(96, (progress / steps.length) * 100) + "%";
    }, 500);

    setTimeout(() => {
        post("setupCharacters");
        setTimeout(() => {
            clearInterval(interval);
            $("loader-fill").style.width = "100%";
            setTimeout(() => {
                hide("loading-screen");
                clearDetail();
                renderSlots();
                show("select-screen");
                post("removeBlur");
            }, 250);
        }, 1750);
    }, 2000);
}

window.addEventListener("message", (event) => {
    const data = event.data;
    switch (data.action) {
        case "ui":
            state.customNationality = data.customNationality;
            translationManager.setTranslations(data.translations);
            state.nationalities = data.countries || [];
            state.characterAmount = data.nChar;
            state.allowDelete = data.enableDeleteButton;
            applyTranslations();
            clearDetail();

            if (data.toggle) {
                startLoadingSequence();
            } else {
                showApp(false);
            }
            break;
        case "setupCharacters": {
            const chars = [];
            for (let i = 0; i < data.characters.length; i++) {
                chars[data.characters[i].cid] = data.characters[i];
            }
            state.characters = chars;
            renderSlots();
            break;
        }
    }
});

/*------------------------------------*\
  EVENTS
\*------------------------------------*/
document.addEventListener("DOMContentLoaded", () => {
    initializeValidator();
    setupNationality();

    $("btn-play").addEventListener("click", () => {
        const char = state.characters[state.selectedSlot];
        if (!char) return;
        post("selectCharacter", { cData: char });
        setTimeout(() => showApp(false), 500);
    });

    $("btn-delete").addEventListener("click", () => {
        if (!state.characters[state.selectedSlot]) return;
        hide("select-screen");
        show("delete-screen");
    });

    $("btn-confirm-delete").addEventListener("click", () => {
        const char = state.characters[state.selectedSlot];
        hide("delete-screen");
        if (char) {
            post("removeCharacter", { citizenid: char.citizenid });
        }
        clearDetail();
        setTimeout(() => show("select-screen"), 500);
    });

    $("btn-cancel-delete").addEventListener("click", () => {
        hide("delete-screen");
        show("select-screen");
    });

    $("btn-close-register").addEventListener("click", closeRegister);
    $("btn-male").addEventListener("click", () => pickGender("male"));
    $("btn-female").addEventListener("click", () => pickGender("female"));
    $("btn-create").addEventListener("click", createCharacter);

    document.addEventListener("keydown", (e) => {
        if (e.key === "Escape" && !$("register-screen").classList.contains("hidden")) {
            closeRegister();
        }
    });
});
